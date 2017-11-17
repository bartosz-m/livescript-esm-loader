concat = (a,...b) -> a.concat ...b.filter (?)

wrap-node = (mapper) ->
    wrapped = -> mapper ...
    wrapped.node = mapper
    for let own k,v of mapper
        unless wrapped[k]
            Object.define-property wrapped, k, 
                enumerable: true
                configurable: false
                get: -> @node[k]
                set: -> @node[k] = it
    wrapped

export default Mapper =
    mappings: []
    
    side-effects: []
    
    fn-call: (input) ->
        result = input
        for m in @mappings
            result = m result
        for side-effect in @side-effects
            side-effect input, result
        result
          
    call: (this-arg, ...args) -> @fn-call args.0
    
    apply: (this-arg, args) -> @fn-call args.0
    
    new: (...mappings) -> wrap-node @create {mappings}
    
    init: ({mappings, side-effects}) !->
        @mappings = concat @mappings, mappings
        @side-effects = concat @side-effects, side-effects
        
    create: (arg) ->
        ^^@
          ..init arg