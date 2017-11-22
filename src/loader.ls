import <[
    assert url fs os path process
    fs-extra livescript source-map-support
    \./Mapper
]>
import \livescript-transform-esm/lib/plugin : transform-esm
import \livescript-transform-esm/lib/livescript/Compiler
import \livescript/lib/lexer
import \process : Process

livescript.lexer = lexer

copy = (something) ->
    type = typeof! something
    if type == \Function
        result = -> something ...
        result.prototype = ^^something.prototype
        result
    else if type == \Object
        ^^something
    else
        something

compiler = Compiler.create {livescript}

transform-esm.install compiler

loader-dependencies =
    \livescript-transform-esm : transform-esm
    \livescript : livescript
    \fs-extra : fs-extra
    \source-map-support : source-map-support

process.on \unhandledRejection, (reason, p) ->
    console.log reason

builtins = new Set do
    Object.keys Process.binding \natives .filter (str) -> /^(?!(?:internal|node|v8)\/)/.test str

RetrieveSourceMap = 
    rules: []
    process: (map-url) ->
        result = null
        for rule in @rules when m = rule.match map-url
            result = rule.map m
            break
        result
    
    bound:~
        -> @process.bind @

source-map-cache = {}

RetrieveSourceMap.rules.push do
    match: -> source-map-cache[it]
    map: -> it


RetrieveSourceMapNode = Mapper.new ({source, map}) ->
    result =
        url: map.url
        map: fs.read-file-sync map.path, \utf8
    result
    
RetrieveSourceMapNode.side-effects.push ({source}, {map}) -> 
    source-map-cache[source.url] = map
      
RetrieveSourceMap.rules.push do
    match: (source) ->
        if file-data = RetrieveFile.process source
            re = /(?:\/\/[@#][ \t]+sourceMappingURL=([^\s'"]+?)[ \t]*$)|(?:\/\*[@#][ \t]+sourceMappingURL=([^\*]+?)[ \t]*(?:\*\/)[ \t]*$)/mg
            while (current-match = re.exec file-data) then last-match = current-match
            if last-match
                source-path = source.match /file\:(?:\/\/)?(.+)/ .1
                source:
                    url: source
                    path: source-path
                map:
                    url: last-match.1
                    path: path.resolve (path.dirname source-path), last-match.1
                    
    map: RetrieveSourceMapNode
        
    
RetrieveFile = 
    rules: []
    process: (fileurl) ->
        result = null
        for rule in @rules when m = rule.match fileurl
            result = rule.map m
            break
        result
    
    bound:~
        -> @process.bind @

RetrieveFile.rules.push do
    match: (file-url) ->
        if m = file-url.match /file\:(?:\/\/)?(.+)/
            if path.is-absolute (filepath = m.1)
                filepath
    map:  ->
        fs.read-file-sync it, \utf8


source-map-support.install do
    override-retrieve-source-map: true
    retrieve-source-map: RetrieveSourceMap.bound
    retrieve-file: RetrieveFile.bound
        
        
root =
    if os.platform! == "win32"
    then process.cwd!split path.sep .0
    else "/"
# 
ensure-dir-sync = (target-dir) !->
  sep = path.sep
  init-dir = if path.is-absolute target-dir
      then sep
      else ''
  target-dir.split sep .reduce do
    (parentDir, childDir) ~>
        cur-dir = path.resolve parent-dir, child-dir
        unless @exists-sync cur-dir
            @mkdir-sync cur-dir
        cur-dir
    , init-dir

fs.ensure-dir-sync = ensure-dir-sync

is-local = (filepath) -> filepath.0 == '.' or path.is-absolute filepath

default-options =
    map: 'linked'
    bare: false
    header: false

ls-ast = (code, options = {}) ->
      ast = livescript-copy.ast code
      output = ast.compile-root options
      output.set-file options.filename
      result = output.to-string-with-source-map!
          ..ast = ast

compile = (ls-code, filepath) ->
    options =
        filename: filepath
    # js-result = ls-ast ls-code, options <<< default-options
    js-result = compiler.compile ls-code, options <<< default-options
    ext = if js-result.ast.exports?length or js-result.ast.imports?length
    then '.mjs'
    else '.js'
    js-result
        ..map-file = filepath.replace /\.ls$/ "#{ext}.map'"
        ..source-map = ..map.to-JSON!        
    # fs.output-file output, js-result.code
    # fs.output-file map-file, JSON.stringify js-result.map.to-JSON!
    

# create temporar directory for compilation
tmp = fs.mkdtemp-sync path.join os.tmpdir!, 'livescript-'

# tmp = path.join process.cwd!, fs.mkdtemp-sync '.livescript-tmp-'
# console.log \TMP tmp

js-to-ls = []

source-path = -> if js-to-ls[it] then that else it

# TODO add default loading of cmj

resolve-local = (specifier, parent-module-URL, default-resolver) ->>
    ext = path.extname specifier
    if ext.length == 0 or ext == '.ls'
        extra-ext = if (ext == '.ls') then '' else  '.ls'
        parent-path = path.dirname source-path parent-module-URL.replace 'file:', ''
        relative-to-tmp = path.resolve root, path.relative tmp,parent-path
        resolved0 = path.resolve parent-path, specifier
        try
            stat = fs.lstat-sync resolved0
        if stat?is-directory!
            resolve-local (path.join resolved0, 'index'), parent-module-URL, default-resolver
        else
            if fs.exists-sync (js-file = resolved0 + '.js')
                default-resolver js-file, parent-module-URL
            else
                resolved = (path.resolve parent-path, specifier) + extra-ext
                if fs.exists-sync resolved
                    file = fs.read-file-sync resolved, \utf8
                    # result = livescript.compile file, filename:resolved
                    result = compile file, resolved
                    output = resolved |> (.replace /\.ls$/,'') |> (+ '.js') |> path.join tmp, _
                    map-file = output  + ".map"
                    map-link = path.basename map-file
                    result.code += "\n//# sourceMappingURL=#map-file\n"
                    fs.ensure-dir-sync path.dirname output
                    fs.write-file-sync output,result.code, \utf8
                    fs.write-file-sync map-file, (JSON.stringify result.source-map), \utf8
                    js-to-ls[output] = resolved
                    js-to-ls['file://'+output] = "file://#{resolved}"
                    url: 'file://'+output
                    format: 'esm'
                else
                    throw new Error "Cannot find module #{specifier} at #{resolved}"
    else
        default-resolver specifier, parent-module-URL



export resolve = (specifier, parent-module-URL, default-resolver ) ->>
    # node cannot retur module used by loader so we need to do it oureselves
    if loader-dependencies[specifier]
        result = 
            url: 'loaded://' + specifier
            format: \dynamic
        return result
        
    if js-to-ls[parent-module-URL]
        parent-module-URL = that
    ext = path.extname specifier
    if ext == '.js'
        console.log \default ext, specifier
        default-resolver specifier,parent-module-URL
    else if is-local specifier
        resolve-local specifier, parent-module-URL, default-resolver 
    else
        default-resolver specifier,parent-module-URL
        # if builtins.has specifier
        #     url: specifier
        #     format: \builtin
        # else
        #     default-resolver specifier,parent-module-URL
            # try
            #     resolved = node-resolve.sync specifier, basedir: parent-path 
            #     console.log \node-resolve specifier, resolved
            #     url: "file://" + resolved
            #     format: \dynamic
            # # if fs.exists-sync path.join specifier
            # catch
            #     console.log \error-default specifier
            #     default-resolver specifier,parent-module-URL


export dynamic-instantiate = (url) ->
    unless url.match /^loaded/
        throw new Error "Unsupported protocol"
    exports: ['default'],
    execute: (exports) ->
        specifier = url.replace 'loaded://', ''
        exports.default.set loader-dependencies[specifier]



# cleanup tmp

process.on \exit !-> fs-extra.remove-sync tmp
