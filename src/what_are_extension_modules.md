[home](https://thomasnyberg.com)

# What are (c)python extension modules?
### 2017-11-12

This writeup is the result of my banging my head against the wall trying to
figure out *what really is going on* with C extension modules. At its core it's
a fairly simple, but it requires (what in hindsight I'd call) some pretty basic
C knowledge that I personally never had coming at things from the python side.
Hopefully this helps others understand this a little better too.


## Contents

1. [The basic setup](#the-basic-setup)
2. [A C extension module](#a-c-extension-module)
3. [Sabotaging our module](#sabotaging-our-module)
4. [Compiling/linking/loading code in C](#compiling_linking_loading-code-in-c)
5. [So how does Python initialize a module?](#so-how-does-python-initialize-a-module)
6. [Conclusion](#conclusion)


## The basic setup <a name="the-basic-setup"></a>

Right now I'm working through this on a debian 9 OS. I presume that everything
here works identically for a recent Ubuntu OS (as well other recent debian
derivatives). If you use another gnu/linux OS, you'll probably need to change
some of the basic commands. If you use something exotic like a Mac or Windows,
then you're on your own. In that case, I'd recommend you *figure it out* or
simply start up a virtual machine with either debian 9 or Ubuntu 16.04
installed.

We will be downloading and compiling our own version of cpython. The first
thing you need to do is to make sure you have the necessary build dependencies
installed. To do this, execute:

    $ sudo apt update
    $ sudo apt build-dep python3.5

Next you'll need to download cpython. You can of course get something super
recent from python's git repo, but I'll stick to the official 3.6.2 release for
stability:

    $ wget https://www.python.org/ftp/python/3.6.2/Python-3.6.2.tar.xz
    $ tar xf Python-3.6.2.tar.xz

This will produce a folder `Python-3.6.2/` in your current directory. Enter
that folder and execute the following:

    $ CFLAGS=-O0 ./configure --prefix=$HOME/opt
    $ make -j 8
    $ make install

The `--prefix` parameter says to install the compiled interpreter in the folder
`$HOME/opt` (`$HOME` is your home folder which for me is `/home/twn`). This
will keep this interpreter separate from the rest of your system allowing easy
uninstallation. The extra `CFLAGS=-O0` says to build *without* optimizations
(which makes it easier to follow the logic when stepping through in a
debugger). The `-j 8` passed to `make` tells it to run (up to) 8 make processes
concurrently resulting in a faster compilation.

Next update your path so that it can find your python interpreter:

    $ export PATH=$HOME/opt/bin:$PATH

The following command print the version and build information of the `python3`
interpreter on my path:

    $ python3 -VV
    Python 3.6.2 (default, Nov 12 2017, 14:37:05)
    [GCC 6.3.0 20170516]

If the version and build info matches your date, you probably have things setup
correctly.

In addition to your own version of cpython, you should also make sure you have
the gnu debugger installed. This can be installed using apt by running:

    $ sudo apt install gdb

## A C extension module <a name="a-c-extension-module"></a>

Before continuing you should probably read the (much better) documentation
found here:

<https://docs.python.org/3/extending/extending.html>  
<https://docs.python.org/3/extending/building.html>

Those pages show you how to write a simple C extension module and it is the
natural starting ground for all of this. After reading those docs and ripping
things apart, you'll probably find that something like the following is roughly
a *minimal* module:

`spammodule.c`
***
    #include <Python.h>

    static struct PyModuleDef spammodule = {
        PyModuleDef_HEAD_INIT,
        "spam",   /* name of module */
    };

    PyMODINIT_FUNC
    PyInit_spam(void) {
        PyObject* m = PyModule_Create(&spammodule);
        if (m == NULL) {
            return NULL;
        }
        return m;
    }
***

Next we need to actually *build* this module in way that python can import.
This is most easily done using the `setuptools` module. The following is a
pretty minimal build script:

`setup.py`
***
    import os
    from setuptools import setup, Extension

    module = Extension('spam', sources=['spammodule.c'])

    setup(name='spam', ext_modules = [module])
***

If you have both `spammodule.c` and `setup.py` in the current directory, the
following should build the software:

    $ python3 setup.py build
    $ python3 setup.py install

Test that everything worked by importing your module:

    $ python3
    >>> import spam
    >>>

If nothing happens (i.e. no error or other issue) then we're flying high.


## Sabotaging our module <a name="sabotaging-our-module"></a>

Somehow our `setup.py` script is converting our C source file into something
that cpython can access. How is this happening? Our `spammodule.c` file defines
only a single function so the natural question is: when/why/how does that
function get executed? An easy way to investigate this is to sabotage our
module and force a crash when the function begins. We will add in the `abort()`
function in the beginning of the `PyInit_spam` function:

`spammodule.c`
***
    #include <Python.h>

    static struct PyModuleDef spammodule = {
        PyModuleDef_HEAD_INIT,
        "spam",   /* name of module */
    };

    PyMODINIT_FUNC
    PyInit_spam(void) {
        abort();
        PyObject* m = PyModule_Create(&spammodule);
        if (m == NULL) {
            return NULL;
        }
        return m;
    }
***

This will force a core dump, but you likely have that turned off by default at
the OS level. First issue the following command:

    $ ulimit -c unlimited

Next build and install the module using `python3 setup.py [build|install]` just
as before. This time if you try to import it you should see the following:

    $ python3
    >>> import spam
    Aborted (core dumped)

This should create a file in the current directory called `core`. This is
the file we will analyze. What we're interested in is seeing the call stack at
the point where the `abort()` was called. This slightly odd command (found
[here](https://www.commandlinefu.com/commands/view/4039/print-stack-trace-of-a-core-file-without-needing-to-enter-gdb-interactively))
should do it for us:

***
    $ gdb -q -n -ex bt -batch $(which python3) core

        ...

    #0  __GI_raise (sig=sig@entry=6) at ../sysdeps/unix/sysv/linux/raise.c:51
    #1  0x00007fe58b5ba3fa in __GI_abort () at abort.c:89
    #2  0x00007fe58ab446a9 in PyInit_spam () at spammodule.c:10
    #3  0x000055ab24e699eb in _PyImport_LoadDynamicModuleWithSpec (spec=0x7fe58b442a20, fp=0x0) at ./Python/importdl.c:154
    #4  0x000055ab24e6921d in _imp_create_dynamic_impl (module=0x7fe58b53d408, spec=0x7fe58b442a20, file=0x0) at Python/import.c:2008
    #5  0x000055ab24e64a9a in _imp_create_dynamic (module=0x7fe58b53d408, args=0x7fe58b4429e8) at Python/clinic/import.c.h:289
    #6  0x000055ab24d8caa5 in PyCFunction_Call (func=0x7fe58b53aea0, args=0x7fe58b4429e8, kwds=0x7fe58b444e10) at Objects/methodobject.c:114

        ...

    #50 0x000055ab24d1c9c2 in run_file (fp=0x7fe58b91f8c0 <_IO_2_1_stdin_>, filename=0x0, p_cf=0x7ffeab2e6df8) at Modules/main.c:338
    #51 0x000055ab24d1d84e in Py_Main (argc=1, argv=0x55ab26f5a010) at Modules/main.c:809
    #52 0x000055ab24cfd04d in main (argc=1, argv=0x7ffeab2e7038) at ./Programs/python.c:69
***

This shows us the stack trace at the location where the `abort()` is called.
The `PyInit_spam` function is called at line #2. Line #3 shows us the function
that calls it which is apparently `_PyImport_LoadDynamicModuleWithSpec` found
at line 154 in file `Python/importdl.c` in the original source tree that we
used to compile the binary. Let's look at the file in question (line numbers
added and some lines removed):

`Python/importdl.c`
***
     89 PyObject *
     90 _PyImport_LoadDynamicModuleWithSpec(PyObject *spec, FILE *fp)
     91 {

        ...

     98     dl_funcptr exportfunc;

        ...

    124     exportfunc = _PyImport_FindSharedFuncptr(hook_prefix, name_buf,
    125                                              PyBytes_AS_STRING(pathbytes),
    126                                              fp);

        ...

    145     p0 = (PyObject *(*)(void))exportfunc;

        ...

    154     m = p0();
***

The `PyInit_spam` function is called at line 154 meaning that this mysterious
`p0` is the `PyInit_spam` function. That `p0` function is apparently loaded at
line 124 by `_PyImport_FindSharedFuncptr`. Well let's use `grep` on our source
tree to find where that function is defined:

***
    $ grep -rn '_PyImport_FindSharedFuncptr('
    Python/importdl.c:21:extern dl_funcptr _PyImport_FindSharedFuncptr(const char *prefix,
    Python/importdl.c:124:    exportfunc = _PyImport_FindSharedFuncptr(hook_prefix, name_buf,
    Python/dynload_shlib.c:55:_PyImport_FindSharedFuncptr(const char *prefix,
    Python/dynload_next.c:30:dl_funcptr _PyImport_FindSharedFuncptr(const char *prefix,
    Python/dynload_dl.c:15:dl_funcptr _PyImport_FindSharedFuncptr(const char *prefix,
    Python/dynload_hpux.c:18:dl_funcptr _PyImport_FindSharedFuncptr(const char *prefix,
    Python/dynload_aix.c:157:dl_funcptr _PyImport_FindSharedFuncptr(const char *prefix,
***

If we investigate these files we'll see that this function is defined in
different ways for different systems. Which one is ours? We can use gdb to
figure that out:

***
    $ gdb $(which python3)

        ...

    (gdb) b _PyImport_FindSharedFuncptr
    Breakpoint 1 at 0x1d5e2b: file ./Python/dynload_shlib.c, line 63.
***

This tells us that our version of the function is defined in
`Python/dynload_shlib.c`. If open that file and step through the function, we
see that the following lines are probably most important:

***
     95     handle = dlopen(pathname, dlopenflags);

        ...

    126     p = (dl_funcptr) dlsym(handle, funcname);
    127     return p;
***

We can print out the values of these variables in `gdb` to see that `pathname`
is
`"/home/twn/opt/lib/python3.6/site-packages/spam-0.0.0-py3.6-linux-x86_64.egg/spam.cpython-36m-x86_64-linux-gnu.so"`
and `funcname` is `"PyInit_spam"`. So the following pseudocode is basically
what acheives the import:

`pseudocode`
***
    handle = dlopen("/path/to/spam.cpython-36m-x86_64-linux-gnu.so");
    p = dlsym(handle, "PyInit_spam");
    (*p)();
***

Now we're finally getting to the core of what's going on here. To understand
the import process we need to understand what `dlopen` and `dlsym` are doing.


## Compiling/linking/loading code in C <a name="compiling_linking_loading-code-in-c"></a>

Now we're going to rewind a bit and try to understand how compilation, linking,
loading, and execution all work (at least at a high-level). First let's go
through a pretty basic function written in C:

`main.c`
***
    #include <stdio.h>

    int func(void) {
        return 7;
    }

    int main(void) {
        printf("%d\n", func());
        return 0;
    }
***

Compile, link and execute it with the following commands:

    $ gcc -c main.c         # compilation
    $ gcc -o main main.o    # linking
    $ ./main                # execution
    7

But now what if we want to separate the code into different files? Let's create
the two following files:

`func.c`
***
    int func(void) {
        return 7;
    }
***

`main.c`
***
    #include <stdio.h>

    int func(void);

    int main(void) {
        printf("%d\n", func());
        return 0;
    }
***

Compile, link and execute it with the following commands:

    $ gcc -c func.c                 # compilation
    $ gcc -c main.c                 # compilation
    $ gcc -o main main.o func.o     # linking
    $ ./main                        # execution
    7

This has changed both our compilation process and the linking process. The
main.c file now needs to have the function declaration for `func`.  This is
required to compile the main.c file because it needs to know how to call `func`
(even if it does not know what it actually does). The second thing that changed
was that we needed to combine these two files into the final main executable.

Producing the separate main.c and func.c files allows us to compile them
separately. However they are still being statically linked. What this means is
that if we want to change func.c we have to recompile and relink everything. A
way of avoiding that is to use shared libraries. Instead of combining the code
from main.c and func.c directly, we add a marker in the main executable saying
to load the code from func.c later. We don't have to change func.c, but we need
to change the compilation and linking process:

    $ gcc -c -fPIC func.c                   # compile using position-independent code
    $ gcc -shared -o libfunc.so func.o      # create a shared library from func.o
    $ gcc -c main.c                         # compile main as before
    $ gcc -o main main.o ./libfunc.so       # link the shared library into main
    $ ./main                                # execute
    7

What changed? The advantage here is that if you want to change func.c you don't
need to do anything with main. For example, change func.c to be the following:

`func.c`
***
    int func(void) {
        return 8;
    }
***

    $ gcc -c -fPIC func.c                   # compile using position-independent code
    $ gcc -shared -o libfunc.so func.o      # create a shared library from func.o
    $ ./main                                # execute without changing main file
    8

Behind the scenes what happens is that when main.c is compiled, the space in
the code where `func` is called is left as an "unresolved symbol". When main is
executed, the dynamic loader loads in the code from `libfunc.so` and replaces
that unresolved symbol with the actual address of the function `func` and only
afterwards starts the actual execution of the binary.

There is a subtle key point here though: "func" is the name of the function in
main. That name is present in the code itself. But what if the main program
does not know the name of the function itself until after it's been
compiled? This is where the functions `dlopen` and `dlsym` come in. Let's
finally change func.c and main.c to the following:

`func.c`
***
    int func7(void) {
        return 7;
    }

    int func8(void) {
        return 8;
    }
***

`main.c`
***
    #include <stdio.h>
    #include <dlfcn.h>

    // This type declaration is needed to call func7() and func8().
    typedef int (*func_ptr_t)(void);

    // This is the full path to the shared library containing func7() and
    // func8().
    const char* sopath = "./libfunc.so";

    int main(int argc, char* argv[]) {
        // Store the name of the function we want to call.
        const char* func_name = argv[1];
        // Open the shared library containing the functions.
        void* lib = dlopen(sopath, RTLD_LAZY);
        // Get a reference to the function we call.
        func_ptr_t func = dlsym(lib, func_name);
        // Call the function and print out the result.
        printf("%d\n", func());
        // Close the library.
        dlclose(lib);
        return 0;
    }
***

Compile, link, and execute as follows:

    $ gcc -c -fPIC func.c                   # compile using position-independent code
    $ gcc -shared -o libfunc.so func.o      # create a shared library from func.o
    $ gcc -c main.c                         # compile as usual
    $ gcc -o main main.o -ldl               # link main to the dl library
    $ ./main func7                          # execute main calling func7
    7
    $ ./main func8                          # execute main calling func8
    8
    $ ./main does_not_exist
    Segmentation fault (core dumped)

So by using `dlopen()` and `dlsym()` we are able to entirely separate the code
in the `main.c` from the code in `func.c`. All that we need is to somehow tell
our code in `main` what code it needs to reference from `libfunc.so`. With this
in hand, we can return to see how this is used to load modules in python.


## So how does Python initialize a module? <a name="so-how-does-python-initialize-a-module"></a>

Python initializes a (C extension) module similarly to the final example in the
previous section. If you look back at the `Python/importdl.c` above, it
basically takes the string `import [name]` and does the following:

    Step 1: Find and open a shared library file called `[name].so`.
    Step 2: Find and load in a function called `PyInit_[name]`.
    Step 3: Execute that function.
    Step 4: Return control back to interpreter.

We can verify this ourselves by removing `setup.py` from the picture. In fact,
if we are willing to accept a broken module, we can remove any references to
python at all in the extension module. Let's change our original `spammodule.c`
file to the following:

`spammodule.c`
***
    #include <stdio.h>

    void* PyInit_spam(void) {
        printf("where is python?\n");
        return 0;
    }
***

And we will compile it as follows:

    $ gcc -shared -fPIC -o spam.so spammodule.c

Let's try importing module:

    $ python3
    >>> import spam
    where is python?
    Traceback (most recent call last):
      File "<stdin>", line 1, in <module>
    SystemError: initialization of spam failed without raising an exception
    >>>

Not a very useful module, but there was no coredump and the interpreter
continues to function. Of course if we actually want to do anything useful with
our module, we will need to import `Python.h` and correctly initialize things,
but what this example shows is that the actual loading of C extensions isn't
really that mysterious.


## Conclusion <a name="conclusion"></a>

As we've seen, C extension modules (on Linux) are really just shared libraries
matching certain conventions so that the interpreter can use the dlopen api to
load in and access a single function. The name of that function is determined
by the name of the module itself. The interpreter executes that function and it
is that function's job to correctly initialize a new module and any C-level
state that it requires. There are many subtleties that were glossed over here,
but hopefully this high-level model is a good starting point in understanding
the details.

Of course Python supports other operating systems as well and it does so by
providing some sort of wrapper around the equivalent runtime dynamic library
loading facilities that that OS provides. So an unflattering and simplified
description of the python interpreter is that it is a new and improved dynamic
loader of compiled C code. Of course this simplification is a bit tongue in
cheek, but I don't believe it's that controversial to claim that the ease with
which Python can interact with C code has had a large effect on its success.

I hope this write up has helped answer some fairly basic questions of how
cpython loads in C extensions, but it hasn't really provided any guidance of
why you might want to write C extensions and what advantages (and
disadvantages) come with such a choice. This will hopefully be the theme of
some future writings.
