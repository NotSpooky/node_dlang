{
    "targets": [{
        "target_name": "module",
        "sources": [ "./src/module.c" ],
        "libraries": [
          "$(PWD)/src/example.a",
          "/usr/lib/libphobos2-ldc-debug.a",
          "/usr/lib/libdruntime-ldc-debug.a"
        ]
    }]
}
