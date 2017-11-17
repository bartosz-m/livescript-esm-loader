[Livescript](https://github.com/gkz/LiveScript) loader for node.js ESM.
Still very WIP.

Enables importing livescript files directly inside modules - files are transpiled on-the-fly.

This loader requires node.js with support for ESM and  livescript [plugin](https://www.npmjs.com/package/livescript-transform-esm) enabling esm.

# Usage
Assuming your main entry point is ./src/index.ls

    node --experimental-modules --loader livescript-esm-loader ./src/index.ls


# License
[BSD-3-Clause](License.md)