## classdumpctl

`classdumpctl` is a command line tool to dump Objective-C class and protocol headers.

`classdumpctl` is built on top of [ClassDumpRuntime](https://github.com/leptos-null/ClassDumpRuntime).

### Usage

`classdumpctl` is designed for 3 primary uses:

- Inspecting a single class or protocol at a time
  - use `-c <class name>` or `-p <protocol name>`
  - the output will be colorized by default (see `-m`)
  - you may need to specify `-i <path>` with the path to the library or framework containing the class or protocol if it's not already loaded
- Dumping a single library or framework
  - use `-i <path>` to specify the path to the binary
  - use `-o <path>` to specify a directory to put the headers in
- Dumping the entire `dyld_shared_cache`
  - use `-a`
  - use `-o <path>` to specify a directory to put the headers in
  - uses concurrency to process all images in the shared cache quickly (see `-j`)

It can also do more. See the full options listing below:

```
Usage: classdumpctl [options]
Options:
  -a, --dyld_shared_cache    Interact in the dyld_shared_cache
                               by default, dump all classes in the cache
  -l, --list                 List all classes in the specified image
                               if specified with -a/--dyld_shared_cache
                               lists all images in the dyld_shared_cache
  -o <p>, --output=<p>       Use path as the output directory
                               if specified with -a/--dyld_shared_cache
                               the file structure of the cache is written to
                               the specified directory, otherwise all classes found
                               are written to this directory at the top level
  -m <m>, --color=<m>        Set color settings, one of the below
                               default: color output only if output is to a TTY
                               never: no output is colored
                               always: output to TTYs, pipes, and files are colored
  -i <p>, --image=<p>        Reference the mach-o image at path
                               by default, dump all classes in this image
                               otherwise may specify --class or --protocol
  -c <s>, --class=<s>        Dump class to stdout (unless -o is specified)
  -p <s>, --protocol=<s>     Dump protocol to stdout (unless -o is specified)
  -j <N>, --jobs=<N>         Allow N jobs at once
                               only applicable when specified with -a/--dyld_shared_cache
                               (defaults to number of processing core available)
```
