import <[ assert ]>
import all './foo.ls'
import all './Vector'

export default ->
    assert true
    # imported from './foo.ls'
    assert Foo, \Foo
    assert Bar, \Bar
    # imported from './Vector'
    assert.deep-equal Zero, x:0,y:0
    try 
        assert false
    catch
        # checking if sourcemaps work
        e.stack.split '\n' .1.match /index\.ls\:13:9/ |> assert