[home](https://thomasnyberg.com)

# Writing cpython extension modules using C++
### 2018-02-22

My [previous](https://thomasnyberg.com/releasing_the_gil.html) article was
nominally about cpython's global interpreter lock, but it also provided a sort of
mini-introduction to writing cpython extension modules using C. Instead this
article focuses on writing extensions using C++. As with my previous articles,
this one is mainly educational. While there are many good reasons to write an
extension using C++, there are also many alternatives (ctypes, cython,
boost-python, pybind11, etc.) which may be more appropriate to your specific
use case. Regardless, understanding how things work under the hood is never a
bad thing!

This article assumes you have gone through the setup process described
[here](https://thomasnyberg.com/what_are_extension_modules.html#the-basic-setup).
That describes how to get a system setup so you can compile and execute all the
code examples of this document.


## Contents

1. [Why use C++?](#why-use-cpp)
2. [A simple C++ extension module](#a-cpp-extension-module)
3. [An aside about name-mangling](#name-mangling)
4. [Advantages of C++](#advantages-cpp)
5. [Caveats of using C++](#caveats)
6. [Conclusion](#conclusion)


## Why use C++? <a name="why-use-cpp"></a>

The upshot of [this](https://thomasnyberg.com/what_are_extension_modules.html)
article is that a C extension module (at least one compiled for cpython on a
debian/Ubuntu OS) is a shared library which (correctly) makes use of the
cpython interpreter C api and which exports one specifically named
initialization function. That means that as long as you can produce a
shared library of that form, it does not really matter what language you use to
do so.  The `setuptools` module (backed internally by the `distutils` module)
provides support for the use of C++ in extension modules as well as C. (See the
`language` keyword parameter of the `Extension` class
[here](https://docs.python.org/3/distutils/apiref.html#distutils.core.Extension).)

My personal reason for using C++ instead of C for my extension modules is
that many of the core components of python correspond closely to the core
components found in C++. This applies to both language constructs (say
exceptions) as well as to the standard library offerings (python lists
correspond to C++ vectors, python dicts corrpond to C++ maps). None of these
correspondences are exact, but they are often close enough that the python code
structure and the C++ code structure can be set to mirror each other very
effectively. In fact, when using techniques of "modern C++", you can very
possibly entirely avoid explicitly using dynamic memory allocation (just as
with python) hopefully allowing for a less bug-prone experience in your
extension modules.


## A simple C++ extension module <a name="a-cpp-extension-module"></a>

Here is a minimal example of a C++ extension module adapted from
[here](https://thomasnyberg.com/what_are_extension_modules.html#a-c-extension-module).

`spammodule.cpp`
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

To *build* this module in way that python can import, we adapt the `setup.py`
file from
[here](https://thomasnyberg.com/what_are_extension_modules.html#a-c-extension-module)
to the following:

`setup.py`
***
    import os
    from setuptools import setup, Extension

    module = Extension('spam', sources=['spammodule.cpp'], language='c++')

    setup(name='spam', ext_modules = [module])
***

If you have both `spammodule.cpp` and `setup.py` in the current directory, the
following should build the software:

    $ python3 setup.py build
    $ python3 setup.py install

Test that everything worked by importing your module:

    $ python3
    >>> import spam
    >>>


## An aside about name-mangling <a name="name-mangling"></a>

The only differences between the versions of the files of the previous section
and those found
[here](https://thomasnyberg.com/what_are_extension_modules.html#a-c-extension-module)
are that

1. The filename of `spammodule.c` has been changed to `spammodule.cpp`; and
2. That the `language='c++'` parameter is passed to the `Extension()` class in
the `setup.py` file.

The reason nothing else needs to change is that the file itself is both valid C
and C++. There is, however, a subtle detail being hidden here. If you have read
through
[this](https://thomasnyberg.com/what_are_extension_modules.html#so-how-does-python-initialize-a-module),
you might remember that the cpython import process looks for a
function specifically called `PyInit_spam` in the shared library which is uses
to initialize the module. But if you also know your C++, you know that it
employs name-mangling to allow for function overloading. Why don't these two
facts cause problems? To make this more concrete, consider the following
example:

`example.c`
***
    void PyInit_spam(void) {
        ;
    }
***

If we compile this file using the C compiler(!) and look at the object's
symbols, we see the following:

    $ gcc -c -o example.o example.c
    $ readelf -a example.o | grep PyInit_spam
         8: 0000000000000000     7 FUNC    GLOBAL DEFAULT    1 PyInit_spam

The `PyInit_spam` string on the right is the symbol of the function in the
compiled object code. However, if we compile using the C++ compiler(!) and look
at the object's symbols, we see this:

    $ g++ -c -o example.o example.c
    $ readelf -a example.o | grep PyInit_spam
         8: 0000000000000000     7 FUNC    GLOBAL DEFAULT    1 _Z11PyInit_spamv

Now that symbol is `_Z11PyInit_spamv`. But if cpython looks for a specific
symbol name when importing the module, how does this name-mangling not confuse
the import process? The reason can be seen by running the pre-processor on our
original `spammodule.cpp` file and ignoring all but the last 16 lines (change
`twn` to your user or whatever you need to make this work on your system):

    $ g++ -E -I/home/twn/opt/include/python3.6m spammodule.cpp | tail -n16
    extern "C" PyObject*
    PyInit_spam(void) {
        PyObject* m = PyModule_Create2(&spammodule, 1013);
        if (m ==
    # 11 "spammodule.cpp" 3 4
                __null
    # 11 "spammodule.cpp"
                    ) {
            return
    # 12 "spammodule.cpp" 3 4
                  __null
    # 12 "spammodule.cpp"
                      ;
        }
        return m;
    }

The output is a bit messy, but the important part is the `extern "C"` listed at
the top. That tells the C++ compiler to specifically _not_ employ name-mangling
for the function `PyInit_spam` and instead to follow the C compiler linking
name standards. In fact, if we change our example file in the same way, we
would see something similar:

`example.c`
***
    extern "C" void PyInit_spam(void) {
        ;
    }
***

    $ g++ -c -o example.o example.c
    $ readelf -a example.o | grep PyInit_spam
         8: 0000000000000000     7 FUNC    GLOBAL DEFAULT    1 PyInit_spam

When writing extensions using C++, the macro `PyMODINIT_FUNC` is very much your
friend. Note that since the import process only ever calls a single function,
no other functions in your file need to be marked with `extern "C"`. Any
internal (i.e. `static`) functions can have their names mangled fine since the
internal calls all respect those manglings and the code still links fine.


## Advantages of C++ <a name="advantages-cpp"></a>

As a way to see the advantages of C++, we will start with the final version of
our multi-threaded C extension module from
[this](https://thomasnyberg.com/releasing_the_gil.html) article (which is
already valid C++ except for a single implicit cast) and iteratively replace
pieces of it with more standard C++ equivalents. The files are almost entirely
unchanged, but I have made the following (mostly cosmetic) changes to the files
to prepare for compilation using C++:

1. I changed the extensions from `.c/.h` to `.cpp/.hpp`.
2. I changed the include guards from `CPRINT_LIST_H` to `CPRINT_LIST_HPP`.
3. I changed the changed the `setup.py` file to reflect these changes and also
added the `language='c++'` parameter to signal that that C++ should be used.

Additionally, I removed the previous implicit cast coming from `malloc` to an
explicit cast to `const char**` since such an implicit cast is not allowed in
C++.

Here are the files I will work with. If you put them all in the same directory,
you should be able to follow through the instructions and have things work.

`spammodule.cpp`
***
    #include <Python.h>

    #include <cprint_list.hpp>

    static PyObject* print_list(PyObject* self, PyObject* args) {
        PyObject* lobj;
        /* Verify that the argument is a list. */
        if (!PyArg_ParseTuple(args, "O!", &PyList_Type, &lobj)) {
            return NULL;
        }
        /* Verify that each member of the list is of type str. */
        for (unsigned int i = 0; i < PyList_Size(lobj); ++i) {
            if (!PyUnicode_Check(PyList_GetItem(lobj, i))) {
                PyErr_SetString(PyExc_TypeError, "must pass in list of str");
                return NULL;
            }
        }
        /* Convert python object to "natural C object" */
        const char** p = (const char**) malloc((PyList_Size(lobj) + 1)*sizeof(const char*));
        for (unsigned int i = 0; i < PyList_Size(lobj); ++i) {
            *(p + i) = PyUnicode_AsUTF8(PyList_GetItem(lobj, i));
        }
        *(p + PyList_Size(lobj)) = NULL;
        Py_BEGIN_ALLOW_THREADS /* <-------- HERE WE RELEASE THE GIL */
        /* Call the C implementation */
        cprint_list(p);
        /* Clean up the C object */
        free(p);
        /* Reacquire the GIL */
        Py_END_ALLOW_THREADS /* <---------- HERE WE ACQUIRE THE GIL */
        Py_RETURN_NONE;
    }

    static PyMethodDef SpamMethods[] = {
        {"print_list", print_list, METH_VARARGS,
         "A function that prints a list of strings."},
        {NULL, NULL, 0, NULL}        /* Sentinel */
    };

    static struct PyModuleDef spammodule = {
        PyModuleDef_HEAD_INIT,
        "spam",   /* name of module */
        "spam module", /* module documentation */
        -1,
        SpamMethods
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

`cprint_list.hpp`
***
    #ifndef CPRINT_LIST_HPP
    #define CPRINT_LIST_HPP

    void cprint_list(const char** p);

    #endif /* CPRINT_LIST_HPP */
***

`cprint_list.cpp`
***
    #include <cprint_list.hpp>

    #include <unistd.h>
    #include <stdio.h>
    #include <pthread.h>

    pthread_mutex_t lock; /* <----------------- HERE IS OUR LOCK! */

    void cprint_list(const char** p) {
        sleep(1);
        pthread_mutex_lock(&lock); /* <-------- HERE WE ACQUIRE THE LOCK */
        while (*p != NULL) {
            printf("%s ", *p);
            p++;
        }
        printf("\n");
        pthread_mutex_unlock(&lock); /* <------ HERE WE RELEASE THE LOCK */
    }
***

`setup.py`
***
    import os
    from setuptools import setup, Extension

    module = Extension('spam', sources=['spammodule.cpp', 'cprint_list.cpp'],
                       include_dirs=['.'], language='c++')

    setup(name='spam', ext_modules = [module])
***

You should be able to build and install them as usual:

    $ python3 setup.py build
    $ python3 setup.py install

The following file can be used to test things out:

`concurrency_test.py`
***
    from threading import Thread
    import spam

    groups = []
    for i in range(5):
        groups.append([str(val) for val in range(i)])

    threads = [Thread(target=spam.print_list, args=(group,)) for group in groups]
    [t.start() for t in threads]
    [t.join() for t in threads]
***

If executing this gives you something like the following output, you're flying
high:

    $ time python3 concurrency_test.py

    0
    0 1
    0 1 2
    0 1 2 3

    real    0m1.076s
    user    0m0.072s
    sys     0m0.004s


### Avoiding explicit dynamic memory management using the C++ standard library

The current version of `spammodule.cpp` converts the python objects to C
objects by allocating a C array of type `const char**`--i.e. an array of
pointers to C strings `const char*`. To do this right we must take care to

1. Correctly use `sizeof()`;
2. Remember to allocate an extra spot for `NULL` to signify the end; and
3. Remember to finally use `free()` to deallocate the dynamic memory when we
are finished.

All of these steps are easy to mess up. In fact, while writing the previous
article, I messed up on _all_ three spots at various times. (Hopefully I have
it right this time!)

All of this is simplified by using the C++ standard library. Instead of using
the `const char*` type, we will use `std::string`; and instead of using
`malloc` to allocate the array, we will use `std::vector` to handle that for
us. Though less essential, we will also convert the usage of `printf()` in
`cprint_list.cpp` to `std::cout` which is a more commonly used by C++
programmers.

First we consider the `cprint_list.[h,c]pp` files. The changes are basically
the "obvious C to C++ changes" (i.e. using `std::string` and `std::vector`,
etc.), but we also made the following choices:

1. We change the parameter type of `cprint_list` to take `const
std::vector<std::string>&` so that we pass our array by constant reference
instead of making any unnecessary copies.
2. We use the language construct `for (const auto& str : strings)` which helps
avoid any off by one errors in addition to being just plain nicer (I am a
python programmer after all!).

`cprint_list.hpp`
***
    #ifndef CPRINT_LIST_HPP
    #define CPRINT_LIST_HPP

    #include <string>
    #include <vector>

    void cprint_list(const std::vector<std::string>& strings);

    #endif /* CPRINT_LIST_HPP */
***

`cprint_list.cpp`
***
    #include <cprint_list.hpp>

    #include <iostream>

    #include <unistd.h>
    #include <pthread.h>

    pthread_mutex_t lock; /* <----------------- HERE IS OUR LOCK! */

    void cprint_list(const std::vector<std::string>& strings) {
        sleep(1);
        pthread_mutex_lock(&lock); /* <-------- HERE WE ACQUIRE THE LOCK */
        for (const auto& str : strings) {
            std::cout << str << " ";
        }
        std::cout << "\n";
        pthread_mutex_unlock(&lock); /* <------ HERE WE RELEASE THE LOCK */
    }
***

Next we change the `print_list()` function in `spammodule.c` to account for
these changes (I'm leaving out the rest of the file):

`print_list()` in `spammodule.cpp`
***
    ...

    static PyObject* print_list(PyObject* self, PyObject* args) {
        PyObject* lobj;
        /* Verify that the argument is a list. */
        if (!PyArg_ParseTuple(args, "O!", &PyList_Type, &lobj)) {
            return NULL;
        }
        /* Verify that each member of the list is of type str. */
        for (unsigned int i = 0; i < PyList_Size(lobj); ++i) {
            if (!PyUnicode_Check(PyList_GetItem(lobj, i))) {
                PyErr_SetString(PyExc_TypeError, "must pass in list of str");
                return NULL;
            }
        }
        /* Convert python object to a "natural C++ object" */
        std::vector<std::string> strings;
        for (unsigned int i = 0; i < PyList_Size(lobj); ++i) {
            strings.push_back(PyUnicode_AsUTF8(PyList_GetItem(lobj, i)));
        }
        Py_BEGIN_ALLOW_THREADS /* <-------- HERE WE RELEASE THE GIL */
        /* Call the C++ implementation */
        cprint_list(strings);
        /* Reacquire the GIL */
        Py_END_ALLOW_THREADS /* <---------- HERE WE ACQUIRE THE GIL */
        Py_RETURN_NONE;
    }

    ...
***

We no longer explicitly manage the memory for our list of strings. This is a
huge win for code simplicity. The `push_back()` method dynamically increases
the size of the vector when necessary (similar to python's `list` class). If we
want, we can reserve that space initially since we know the size of the list,
but I think even that should only be done if it's known to be a bottleneck. In
such a simple module these changes may seem small, but when dealing with more
complicated code, avoiding explicit memory management can help avoid many hard
to understand bugs.


### RAII

RAII stands for "resource acquisition is initialization". The name leaves a bit
to be desired, but the concept is very powerful indeed.  Basically it means
that when a class is allocated on the stack its constructor is called and when
the program reaches the end of the enclosing scope of that class its destructor
is called automatically. This is similar to a context manager in python. RAII
is very effective for resource management. The idea is to acquire resources in
the constructor and release them in the destructor. Since the destructor is
called automatically for you, you should not end up with any resource leak by
forgetting to release the resource.

Let's make this explicit with a very simple example. In the following example,
we define a class `C`. We define it's constructor and destructor by defining
public class methods with the names `C` and `~C` respectively--i.e. the same
name as the class or the same name as the class with `~` prepended. All the
constructor and destructor do is print out when they are called so that we can
follow the code's execution.

`example.cpp`
***
    #include <iostream>

    class C {
      public:
        C(void) { std::cout << "constructor\n"; };
        ~C(void) { std::cout << "destructor\n"; };
    };

    int main(void) {
        {
          C c; /* <-- CONSTRUCTOR IS CALLED */
          std::cout << "inside block\n";
          /* DESTRUCTOR IS CALLED AUTOMATICALLY */
        }
        std::cout << "outside block\n";
        return 0;
    }
***

If you compile and execute that file you see the following:

    $ g++ -o example example.cpp
    $ ./example
    constructor
    inside block
    destructor
    outside block

The constructor and destructor are both called automatically and (importantly)
the destructor is called at the end of the scope _before_ the final `"outside
block\n"` string is printed.

RAII is used throughout the C++ standard library meaning that this technique is
available to you already without the requirement that you employ the technique
explicitly. Let's make some changes to `print_list()` in `spammodule.cpp` to
take advantage of this. Firstly, notice that in our current version of
`print_list()` we first run through the python list `lobj` to test that all the
members of the list are python `str` objects and then returning a python
exception if that test fails. I would personally prefer that test to occur at
the same time as the populating of the `std::vector<std::string>` object
`strings`. The reason I chose not to do this before was because then I would
have to be even more careful about using `malloc/free`, but I decided against
it since that is something that is easy to mess up. But with RAII it is quite
easy. Consider instead the following version of `print_list()`:

`print_list()` in `spammodule.cpp`
***
    ...

    static PyObject* print_list(PyObject* self, PyObject* args) {
        PyObject* lobj;
        /* Verify that the argument is a list. */
        if (!PyArg_ParseTuple(args, "O!", &PyList_Type, &lobj)) {
            return NULL;
        }
        /* Convert python object to a "natural C++ object" */
        std::vector<std::string> strings;
        for (unsigned int i = 0; i < PyList_Size(lobj); ++i) {
            PyObject* sobj = PyList_GetItem(lobj, i);
            /* Verify that python object is of type str. */
            if (!PyUnicode_Check(sobj)) {
                PyErr_SetString(PyExc_TypeError, "must pass in list of str");
                return NULL;
            }
            strings.push_back(PyUnicode_AsUTF8(sobj));
        }
        Py_BEGIN_ALLOW_THREADS /* <-------- HERE WE RELEASE THE GIL */
        /* Call the C++ implementation */
        cprint_list(strings);
        /* Reacquire the GIL */
        Py_END_ALLOW_THREADS /* <---------- HERE WE ACQUIRE THE GIL */
        Py_RETURN_NONE;
    }

    ...
***

Now we go through the list object `lobj` only one time. If we find an object
that is not a python `str`, we just set the exception and return NULL. In this
case, the partially constructed `strings` object is automatically deallocated
and no memory leak will occur. In my opinion, this makes the error-handling and
conversion much easier to follow and decreases the likelihood of both missing
some error-handling as well as deallocating memory.

**Note**: The `std::vector<std::string>` object will make extra copies of the
strings (i.e. the underlying data pointed to by `const char*`) even though this
is unnecessary by the object lifetime of python. We could instead use
`std::vector<const char*>` if this optimization were necessary, but if it is
not, it is probably better to use the more standard C++ string class.

RAII is good for resource management, but memory is not the only resource of a
system. It is also great for handling locks and helping avoid deadlock. Next we
convert our usage of the `pthread_mutex_t` lock to `std::mutex` which is
more common in C++. Not only that, we will use `std::lock_guard` to use RAII in
conjunction with the lock. This will acquire the lock when it is allocated and
it will automatically release it when the end of the enclosing scope is
reached. We no longer have to worry about accidentally forgetting to release
the lock! Here is our new version of the `cprint_list.cpp` file:

`cprint_list.cpp`
***
    #include <cprint_list.hpp>

    #include <iostream>
    #include <mutex>

    #include <unistd.h>

    std::mutex mtx; /* <----------------- HERE IS OUR LOCK! */

    void cprint_list(const std::vector<std::string>& strings) {
        sleep(1);
        std::lock_guard<std::mutex> lck(mtx); /* <-------- HERE WE ACQUIRE THE LOCK */
        for (const auto& str : strings) {
            std::cout << str << " ";
        }
        std::cout << "\n";
        /* HERE THE LOCK IS AUTOMATICALLY RELEASED! */
    }
***

This is all great, but we can also use RAII to improve code in `spammodule.cpp`
file as well. We will do this by creating a `GilReleaser` class which will use
RAII to release/acquire the GIL. To do this we need to know what the
`Py_BEGIN_ALLOW_THREADS` and `Py_END_ALLOW_THREADS` macros actually do.
[This](https://docs.python.org/3/c-api/init.html#releasing-the-gil-from-extension-code)
page tells us that

    Py_BEGIN_ALLOW_THREADS
    ...
    Py_END_ALLOW_THREADS

expands to

    PyThreadState *_save;
    _save = PyEval_SaveThread();
    ...
    PyEval_RestoreThread(_save);

This means that if we want to use RAII we should put the first part in our
class' constructor and the second part in its destructor. In other words, the
following should suffice:

    class GilReleaser {
        public:
            GilReleaser(void) { thread_state = PyEval_SaveThread(); }
            ~GilReleaser(void) { PyEval_RestoreThread(thread_state); }
        private:
            PyThreadState* thread_state = NULL;
    };

We can make use of the `GilReleaser` class as follows:

`print_list()` in `spammodule.cpp`
***
    ...

    class GilReleaser {
        public:
            GilReleaser(void) { thread_state = PyEval_SaveThread(); }
            ~GilReleaser(void) { PyEval_RestoreThread(thread_state); }
        private:
            PyThreadState* thread_state = NULL;
    };

    static PyObject* print_list(PyObject* self, PyObject* args) {
        PyObject* lobj;
        /* Verify that the argument is a list. */
        if (!PyArg_ParseTuple(args, "O!", &PyList_Type, &lobj)) {
            return NULL;
        }
        /* Convert python object to a "natural C++ object" */
        std::vector<std::string> strings;
        for (unsigned int i = 0; i < PyList_Size(lobj); ++i) {
            PyObject* sobj = PyList_GetItem(lobj, i);
            /* Verify that python object is of type str. */
            if (!PyUnicode_Check(sobj)) {
                PyErr_SetString(PyExc_TypeError, "must pass in list of str");
                return NULL;
            }
            strings.push_back(PyUnicode_AsUTF8(sobj));
        }
        /* Call the C++ implementation */
        {
            GilReleaser gil_releaser;
            cprint_list(strings);
        }
        Py_RETURN_NONE;
    }

    ...
***

The GIL is now released when entering the block scope containing
`cprint_list()` and acquired when leaving it. If we had more functions in this
extension module, we could just drop this class in any area that should release
the GIL and let the C++ compiler handle the rest!


### Exceptions

C++ has exceptions which can be used similarly to those in python. What really
makes them shine is that they work well with RAII. If an exception is thrown,
the call stack is "unwound" until it is caught and handled.  During this
unwinding, all destructors are called in the same way as if execution reached
the end of a scope without an exception having been called. The C++ exceptions
themselves behave similarly to python exceptions and they can be mapped back
quite naturally. To be more clear, look at this example:

`example.cpp`
***
    #include <iostream>
    #include <exception>

    class C {
      public:
        C(void) { std::cout << "constructor\n"; };
        ~C(void) { std::cout << "destructor\n"; };
    };

    int main(void) {
        try {
          C c; /* <-- CONSTRUCTOR IS CALLED */
          throw std::exception{};
          /* DESTRUCTOR IS CALLED AUTOMATICALLY */
        } catch (const std::exception& exc) {
          std::cout << "caught exception\n";
        }
        std::cout << "outside block\n";
        return 0;
    }
***

    $ g++ -o example example.cpp
    $ ./example
    constructor
    destructor
    caught exception
    outside block

As seen above, the destructor is called _before_ the code in the `catch` block
is executed.

We will now change the implementation of our `cprint_list` to throw some
different exceptions. Before discussing the changes, here are our new
`cprint_list.[h,c]pp` files:

`cprint_list.hpp`
***
    #ifndef CPRINT_LIST_HPP
    #define CPRINT_LIST_HPP

    #include <string>
    #include <vector>
    #include <exception>

    void cprint_list(const std::vector<std::string>& strings);

    class BaseError : public std::exception {
        public:
            BaseError(std::string msg) : _msg{msg} {}
            virtual const char* what() const noexcept { return _msg.c_str(); }
        private:
            const std::string _msg;
    };

    class IntegerError : public BaseError {
        public:
            IntegerError(std::string msg) : BaseError{msg} {}
    };

    class PositivityError : public BaseError {
        public:
            PositivityError(std::string msg) : BaseError{msg} {}
    };

    #endif /* CPRINT_LIST_HPP */
***

`cprint_list.cpp`
***
    #include <cprint_list.hpp>

    #include <iostream>
    #include <mutex>

    #include <unistd.h>

    std::mutex mtx; /* <----------------- HERE IS OUR LOCK! */

    static void validate_str(const std::string& str) {
        // Verify that the string represents a valid integer
        std::string::const_iterator it = str.begin();
        if (*it != '-' and !(std::isdigit(*it))) {
            throw IntegerError("invalid integer: '" + str + "'");
        }
        ++it;
        for ( ; it != str.end(); ++it ) {
            if (!std::isdigit(*it)) {
                throw IntegerError("invalid integer: '" + str + "'");
            }
        }
        // Verify that the string represents a non-negative integer
        if (*(str.begin()) == '-') {
            throw PositivityError("not a positive integer: '" + str + "'");
        }
    }

    void cprint_list(const std::vector<std::string>& strings) {
        sleep(1);
        for (const auto& str : strings) {
            validate_str(str);
        }
        std::lock_guard<std::mutex> lck(mtx); /* <-------- HERE WE ACQUIRE THE LOCK */
        for (const auto& str : strings) {
            std::cout << str << " ";
        }
        std::cout << "\n";
    }
***

The new `cprint_list` function requires that the vector of strings contain only
valid non-negative integers. Here the definition of "integers" is a string of
characters that (optionally) starts with `-` and then contains only digits
`0-9`. For example, `-0000001` is a valid integer, but `--0000001` and `00-1`
are not. Here the definition of a "non-negative" integer is an integer which
does not start with `-`.

The `cprint_list` function now does two tests. It first checks if any of the
strings is not a valid integer and throws an `IntegerError` in that case.
It then checks if any of these integers is negative and throws a
`PositivityError` exception if it finds one. Both of these C++ exceptions inherit
from a base exception `BaseError`.

Next we define python exceptions corresponding to these and translate between
them. Here is our new `spammodule.cpp` file:

`spammodule.cpp`
***
    #include <Python.h>

    #include <cprint_list.hpp>

    static PyObject* BaseErrorObj;
    static PyObject* IntegerErrorObj;
    static PyObject* PositivityErrorObj;

    static void set_python_exception(const BaseError& e) {
        // Map error to correct python exception.
        if (dynamic_cast<const IntegerError*>(&e)) {
            PyErr_SetString(IntegerErrorObj, e.what());
        } else if (dynamic_cast<const PositivityError*>(&e)) {
            PyErr_SetString(PositivityErrorObj, e.what());
        } else {
            PyErr_SetString(BaseErrorObj, e.what());
        }
    }

    class GilReleaser {
        public:
            GilReleaser(void) { thread_state = PyEval_SaveThread(); }
            ~GilReleaser(void) { PyEval_RestoreThread(thread_state); }
        private:
            PyThreadState* thread_state = NULL;
    };

    static PyObject* print_list(PyObject* self, PyObject* args) {
        PyObject* lobj;
        /* Verify that the argument is a list. */
        if (!PyArg_ParseTuple(args, "O!", &PyList_Type, &lobj)) {
            return NULL;
        }
        /* Convert python object to a "natural C++ object" */
        std::vector<std::string> strings;
        for (unsigned int i = 0; i < PyList_Size(lobj); ++i) {
            PyObject* sobj = PyList_GetItem(lobj, i);
            /* Verify that python object is of type str. */
            if (!PyUnicode_Check(sobj)) {
                PyErr_SetString(PyExc_TypeError, "must pass in list of str");
                return NULL;
            }
            strings.push_back(PyUnicode_AsUTF8(sobj));
        }
        /* Call the C++ implementation */
        try {
            GilReleaser gil_releaser;
            cprint_list(strings);
        } catch (const BaseError& e) {
            set_python_exception(e);
            return NULL;
        }
        Py_RETURN_NONE;
    }

    static PyMethodDef SpamMethods[] = {
        {"print_list", print_list, METH_VARARGS,
         "A function that prints a list of strings."},
        {NULL, NULL, 0, NULL}        /* Sentinel */
    };

    static struct PyModuleDef spammodule = {
        PyModuleDef_HEAD_INIT,
        "spam",   /* name of module */
        "spam module", /* module documentation */
        -1,
        SpamMethods
    };

    PyMODINIT_FUNC
    PyInit_spam(void) {
        PyObject* m = PyModule_Create(&spammodule);
        if (m == NULL) {
            return NULL;
        }
        // Set up all exceptions.
        BaseErrorObj = PyErr_NewException("spam.BaseError", NULL, NULL);
        Py_INCREF(BaseErrorObj);
        PyModule_AddObject(m, "BaseError", BaseErrorObj);
        IntegerErrorObj = PyErr_NewException("spam.IntegerError", BaseErrorObj, NULL);
        Py_INCREF(IntegerErrorObj);
        PyModule_AddObject(m, "IntegerError", IntegerErrorObj);
        PositivityErrorObj = PyErr_NewException("spam.PositivityError", BaseErrorObj, NULL);
        Py_INCREF(PositivityErrorObj);
        PyModule_AddObject(m, "PositivityError", PositivityErrorObj);
        return m;
    }
***

There are more things going on than before, but they're not that bad:

1. We define three python exceptions `BaseError`, `IntegerError`, and
`PositivityError`. They are declared at the top of the file and actually
created in the `PyInit_spam` function. Note that `IntegerError` and
`PositivityError` inherit from `BaseError` corresponding to the structure in the
C++ code.
2. We define a function `set_python_exception` which takes an incoming C++
exception and converts it to the corresponding python exception.
3. We added a try/catch block around the `cprint_list()` call.

In all of these changes there are two places where the exceptions and RAII
really work well together. The first is in `cprint_list` with the lock that it
acquires. The function `validate_str` could throw an exception, but due to the
RAII `lock_guard`, that lock will be automatically released in that case. The
second place where exceptions and RAII play well is in the try/catch block in
the `spammodule.cpp` file. If a C++ exception is thrown when `cprint_list()`
executes, the GilReleaser's destructor is automatically called before entering
the catch block portion of the code. The reason why this is important for us is
because it means that the GIL will once again be acquired before the
`set_python_exception()` function is called.  That function makes use of the
python C api directly and hence should not be called until after the GIL is
acquired.

**Warning:** If you want a robust C++ extension, you will need to be sure to
catch any C++ exeptions before they make it back into "python land" (whether
you translate them or not). The reason for this is the following: if an
exception is not caught anywhere in the stack, then `terminate()` is called
which may or may not do stack unwinding. This means not only will you kill the
interpreter, but you might not have destructors called (which doesn't really
matter for locks, but might for something else). Even if you don't care about
the destructors, you probably don't want a total crash of the interpreter. For
a concrete example, see the following:

`example.cpp`
***
    #include <iostream>
    #include <exception>

    class C {
      public:
        C(void) { std::cout << "constructor\n"; };
        ~C(void) { std::cout << "destructor\n"; };
    };

    int main(void) {
        {
          C c; /* <-- Constructor is called */
          /* THIS IS NOT CAUGHT ANYWHERE */
          throw std::exception{};
        }
        std::cout << "outside block\n";
        return 0;
    }
***

    $ g++ -o example example.cpp
    $ ./example
    constructor
    terminate called after throwing an instance of 'std::exception'
      what():  std::exception
    Aborted

Note that on my system the destructor was never called!


## Caveats of using C++ <a name="caveats"></a>

After a section espousing the advantages of writing an extension in C++, it
would only be fair to talk about the caveats as well. Firstly, by following a
process similar to the one presented here, you effectively are taking on the
maintainence burden of directly using the C api.  This can make supporting
different versions of the cpython interpreter more difficult (if you need to
provide that support). Also on top of everything, you are effectively marrying
your extension to the cpython interpreter.

Beyond the C api, you are taking on the burden of C++. C++ has many
advantages, but it is not a language for the faint-hearted. It can take a very
long time before you feel comfortable in C++. Even if you limit yourself to
certain portions of the language (say not much more than is presented here),
you will almost certainly run into the rest of the complexity some day and it
will exercise (and frustrate) your brain. (Though as with any other muscle,
this will make it grow.) As an example of this complexity, I must admit that I
had to ask some questions on reddit when I tried to use `dynamic_cast<T>` in
this document. Even after years of C++, I had fundamental misunderstandings of
how it works. Know that using C++ is a fruitful, but humbling experience.


## Conclusion <a name="conclusion"></a>

I hope this document has provided a good explanation of how to write a cpython
extension in C++ and helps remove some of the mystery of how cpython works.
Once you understand the fundamentals, you can write extensions in basically any
language as long as you can (and are willing to do the work of) tie things
together with the C api.
