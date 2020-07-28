{
    "targets": [{
        "target_name": "module",
        "sources": [ "./src/example.s", "./src/dlang_node.s", "./src/module.c" ],
        "libraries": [
          "/usr/lib/libphobos2-ldc-debug.a",
          "/usr/lib/libdruntime-ldc-debug.a"
        ]
    }]
}
