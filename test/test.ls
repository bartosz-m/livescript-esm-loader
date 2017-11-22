import <[ assert ]>
import \livescript
import \./cjs
import all './foo.ls'
import all './Vector'


export default ->
    assert.deep-equal cjs, name: "CommonJS Module"
    assert livescript, 'loading cjs module with defined main entry'
    # imported from './foo.ls'
    assert Foo, \Foo
    assert Bar, \Bar
    # imported from './Vector'
    assert.deep-equal Zero, x:0,y:0
    try 
        assert false
    catch
        # checking if sourcemaps work
        e.stack.split '\n' .1.match /test\.ls\:17:9/ |> assert