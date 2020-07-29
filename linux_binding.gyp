{
    "targets": [{
        "target_name": "module",
        "sources": [ "./src/module.c" ],
        "libraries": [
          "/usr/lib/libphobos2-ldc-debug.a",
          "/usr/lib/libdruntime-ldc-debug.a",
          "$(PWD)/src/example.a"
        ]
    }]
}
