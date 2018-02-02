[home](https://thomasnyberg.com)

# Releasing the gil
### 2018-02-06

This is a sort of continuation of a previous article: [What are (c)python
extension modules?](https://thomasnyberg.com/what_are_extension_modules.html).
That article took a fairly low-level look at what is actually going on with
python C extension modules. This article instead focuses on one of the most
common topics of confusion, complaints, etc. in the land of (c)python: the
global interpreter lock (GIL).

The GIL is a lock held by the python interpreter process whenever bytecode is
being executed _unless_ it is explicitly released.  I.e. the design of the
cpython interpreter is to assume that whatever that occurs in the cpython
process between bytecodes is dangerous and not thread-safe unless told
otherwise by the programmer. This means that the lock is enabled by default and
that it is periodically released as opposed to the paradigm often seen in many
multi-threaded programs where locks are generally not held except when
specifically required in so-called "critical sections" (parts of code which are
not thread-safe).

Instead of making any criticisms of or taking any positions on the design of
cpython, this article goes through an example of writing a C-extension
module and using it to release the cpython global interpreter lock. The
extension module itself will be about as simple as possibly while still
retaining enough complexity to demonstrate both the need for and the
difficulties of writing C extensions that release the GIL.

This article makes no attempt at being cross-platform or interpreter-agnostic.
It focuses exclusively on the cpython interpreter version 3.6.2 running on
debian/Ubuntu. Its purpose is purely educational. If you are writing an
extension you should consider whether something cross-platform or
interpreter-agnostic would be more appropriate (and whether an extension is
even truly necessary). In that case you should also be aware of cython, ctypes,
etc. and consider if those provide a better development base than anything
here.

This article assumes you have gone through the setup process described
[here](https://thomasnyberg.com/what_are_extension_modules.html#the-basic-setup).
That describes how to get system setup so you can compile and execute all the
code examples of this document.

## Contents

1. [A simple C extension](#simple-c-extension)
2. [Some discussion regarding the C extension](#discussion-regarding-extension)
3. [Executing our extension code concurrently and releasing the gil](#executing-concurrently)
4. [Race conditions...](#race-conditions)
5. [A pure python implementation of the extension](#pure-python)
6. [Conclusion](#conclusion)


## A simple C extension <a name="simple-c-extension"></a>

We are going to start with our basic module from
[here](https://thomasnyberg.com/what_are_extension_modules.html#a-c-extension-module)
except this time we will add a single function that allows us to print a list
of strings. In addition to printing the strings, it will sleep for 1 second
which is meant to simulate some sort of asynchronous operation. The function
will handle python type errors for its parameters, but I skip any internal C
error-handling (e.g. checking the return values for `malloc`, `printf`, etc.).
Without further ado, here is our module:

`spammodule.c`
***
    #include <Python.h>

    /* C implementation of our print list function */
    static void cprint_list(const char** p) {
        sleep(1);
        while (*p != NULL) {
            printf("%s ", *p);
            p++;
        }
        printf("\n");
    }

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
        const char** p = malloc((PyList_Size(lobj) + 1)*sizeof(const char*));
        for (unsigned int i = 0; i < PyList_Size(lobj); ++i) {
            *(p + i) = PyUnicode_AsUTF8(PyList_GetItem(lobj, i));
        }
        *(p + PyList_Size(lobj)) = NULL;
        /* Call the C implementation */
        cprint_list(p);
        /* Clean up the C object */
        free(p);
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

To build this extension we use the following setuptools build script:

`setup.py`
***
    import os
    from setuptools import setup, Extension

    module = Extension('spam', sources=['spammodule.c'])

    setup(name='spam', ext_modules = [module])
***

Put both of these files in the same directory and execute the following
commands to build and install the software:

    $ python3 setup.py build
    $ python3 setup.py install

Test that everything worked by importing the module and calling the function:

    $ python3
    >>> import spam
    >>> spam.print_list(['a', 'b', 'c'])
    a b c


## Some discussion regarding the C extension <a name="discussion-regarding-extension"></a>

The only parts of our `spammodule.c` file that are not boilerplate are the
`cprint_list()` and `print_list()` functions. The job of the `cprint_list()`
function is to

1. Immediately sleep for 1 second; and
2. Print out the strings pointed to by its parameter separated by spaces and
then ending with a newline.

The job of the `print_list()` function is to

1. Verify that there is only a single parameter is passed to it and that that
parameter is a python list whose members are all python str objects;
2. Convert the python object to a "natural C object";
3. Call the `cprint_list()` function on that C object;
4. Free the memory allocated for the C object; and
5. Return control back to the main interpreter.

The reason I am going through the trouble of steps (2) and (4) are that I want
to have a strict separation between "python land" and "C land". I.e. I want the
C implementation to know nothing about python and I want there to be a minimal
translation layer between the two "code contexts". This is entirely for code
clarity and ease of programmer understanding. This example is so simple that
this separation is not really necessary, but if the internal C code were more
complicated, such a code design is critical. If we wanted to, we could take the
`cprint_list()` function and move it out of the `spammodule.c` itself.

In fact, as a demonstration we will do so now. Next we will separate the code
for `cprint_list()` into separate header and implementation files
`cprint_list.h` and `cprint_list.c`. We also need to edit our `setup.py` file
to reflect this. Here is how the code files show look now:

`spammodule.c`
***
    #include <Python.h>

    #include <cprint_list.h>

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
        const char** p = malloc((PyList_Size(lobj) + 1)*sizeof(const char*));
        for (unsigned int i = 0; i < PyList_Size(lobj); ++i) {
            *(p + i) = PyUnicode_AsUTF8(PyList_GetItem(lobj, i));
        }
        *(p + PyList_Size(lobj)) = NULL;
        /* Call the C implementation */
        cprint_list(p);
        /* Clean up the C object */
        free(p);
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

`cprint_list.h`
***
    #ifndef CPRINT_LIST_H
    #define CPRINT_LIST_H

    void cprint_list(const char** p);

    #endif /* CPRINT_LIST_H */
***

`cprint_list.c`
***
    #include <cprint_list.h>

    #include <unistd.h>
    #include <stdio.h>

    void cprint_list(const char** p) {
        sleep(1);
        while (*p != NULL) {
            printf("%s ", *p);
            p++;
        }
        printf("\n");
    }
***

`setup.py`
***
    import os
    from setuptools import setup, Extension

    module = Extension('spam', sources=['spammodule.c', 'cprint_list.c'],
                       include_dirs=['.'])

    setup(name='spam', ext_modules = [module])
***

With this separation in place, we can keep all C development in the
`cprint_list.c` file. In any real project it would be a good idea to write some
tests that specifically make use of the C code without any knowledge of the
python code.


## Executing our extension code concurrently and releasing the gil <a name="executing-concurrently"></a>

The original point of this article is to discuss concurrency and the GIL so we
need a python program that exhibits this. The following is our first attempt at
using `spam.print_list()` in a concurrent fashion:

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

If we run (and time) this program, we see the following:

    $ time python3 concurrency_test.py

    0
    0 1
    0 1 2
    0 1 2 3

    real    0m5.053s
    user    0m0.060s
    sys     0m0.008s

It takes 5 seconds to run and it prints out about once a second. This means
our usage of threads doesn't really gain us anything right now. The reason for
this is because our C extension is holding on to the cpython interpreter's
GIL throughout the program.  If we want to release that lock, we must do so
explicitly ourselves. We can do that by making use of the
`Py_BEGIN_ALLOW_THREADS` and `Py_END_ALLOW_THREADS` macros. The first releases
the lock while the second acquires it. To use these macros, we need to change
the `print_list()` function in `spammodule.c` to the following (I'm leaving out
the rest of the file):

`print_list()`
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
        /* Convert python object to "natural C object" */
        const char** p = malloc((PyList_Size(lobj) + 1)*sizeof(const char*));
        for (unsigned int i = 0; i < PyList_Size(lobj); ++i) {
            *(p + i) = PyUnicode_AsUTF8(PyList_GetItem(lobj, i));
        }
        *(p + PyList_Size(lobj)) = NULL;
        Py_BEGIN_ALLOW_THREADS /* <-------- HERE WE RELEASE THE GIL */
        /* Call the C implementation */
        cprint_list(p);
        /* Clean up the C object */
        free(p);
        /* Reaquire the GIL */
        Py_END_ALLOW_THREADS /* <---------- HERE WE ACQUIRE THE GIL */
        Py_RETURN_NONE;
    }

    ...
***

If we now rebuild our module and run the `concurrency_test.py` file again, we
see the following sort of output:

    $ time python3 concurrency_test.py

    0
    0 1
    0 1 2
    0 1 2 3

    real    0m1.113s
    user    0m0.108s
    sys     0m0.004s

Success! We have successfully run the different threads concurrently. However,
there is now a new problem with our code...


## Race conditions...  <a name="race-conditions"></a>

Unfortunately the current form of our code contains a race condition. We will
change our concurrency test file to the following which will make it apparent:

`concurrency_test.py`
***
    from threading import Thread
    import spam

    groups = []
    for i in range(10000):
        groups.append([str(val) for val in range(i % 10)])

    threads = [Thread(target=spam.print_list, args=(group,)) for group in groups]
    [t.start() for t in threads]
    [t.join() for t in threads]
***

This test creates more threads than before (10000 of them) and prints more
output. We would expect each line to start with 0 and then count up
consecutively and end in an integer between 0 and 8. We can test that theory by
piping the output through the unix `sort` and `uniq` commands. However, if we
execute this we are likely to see something like the following:

    $ python3 concurrency_test.py | sort | uniq

    0
    0 0
    0 1
    0 1 2
    0 1 2 3
    0 1 2 3 0 4 1 5 6 2 0
    0 1 2 3 4
    0 1 2 3 4 5
    0 1 2 3 4 5 6
    0 1 2 3 4 5 6 7
    0 1 2 3 4 5 6 7 8
    1 2 0
    1 2 3 3 4 5 6 7 8
    1 2 3 4 5 6 7 8

The issue is that our C function `cprint_list()` is _not_ thread-safe.
Now that we have released the global interpreter lock it is our responsibility
to write thread-safe code. There are essentially two parts to the
`cprint_list()` function. The first is the portion that sleeps and the second
is the portion that actually prints output. There is no race condition in the
sleep portion of the code, but there is one in the printing portion. That means
that we now need a lock around the printing portion. We can have one by editing
the `cprint_list.c` file to the following:

`cprint_list.c`
***
    #include <cprint_list.h>

    #include <unistd.h>
    #include <stdio.h>
    #include <pthread.h>

    pthread_mutex_t lock; /* <----------------- HERE IS OUR NEW LOCK! */

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

If you rebuild everything and run the concurrency test again you see the
following:

    $ python3 concurrency_test.py | sort | uniq

    0
    0 1
    0 1 2
    0 1 2 3
    0 1 2 3 4
    0 1 2 3 4 5
    0 1 2 3 4 5 6
    0 1 2 3 4 5 6 7
    0 1 2 3 4 5 6 7 8


## A pure python implementation of the extension <a name="pure-python"></a>

In fact, nothing in this document ever really required moving to C. The python
standard library has the `time` module with the `sleep()` function. That
function (at least the version for my system) is implemented in
`./Modules/timemodule.c` in the 3.6.2 version of python as follows:

`./Modules/timemodule.c`
***
    ...

    1434         if (_PyTime_AsTimeval(secs, &timeout, _PyTime_ROUND_CEILING) < 0)
    1435             return -1;
    1436 
    1437         Py_BEGIN_ALLOW_THREADS
    1438         err = select(0, (fd_set *)0, (fd_set *)0, (fd_set *)0, &timeout);
    1439         Py_END_ALLOW_THREADS
    1440 
    1441         if (err == 0)
    1442             break;
    1443 
    1444         if (errno != EINTR) {
    1445             PyErr_SetFromErrno(PyExc_OSError);
    1446             return -1;
    1447         }

    ...
***

It is line 1438 where the final sleep functionality is implemented and
immediately before and after you can see that the global interpreter lock is
released.

With this knowledge, we can write a similar `print_list()` function in python
as follows:

`pprint_list.py`
***
    import time

    def print_list(strings):
        time.sleep(1)
        for s in strings:
            print(s, end=' ')
        print()
***

However this has just the same race condition as before. We can verify it by
adapting our old concurrency test to use the pure python implementation:

`pure_concurrency_test.py`
***
    from threading import Thread
    import time

    def print_list(strings):
        time.sleep(1)
        for s in strings:
            print(s, end=' ')
        print()

    groups = []
    for i in range(10000):
        groups.append([str(val) for val in range(i % 10)])

    threads = [Thread(target=print_list, args=(group,)) for group in groups]
    [t.start() for t in threads]
    [t.join() for t in threads]
***

If you run it you can expect to see something similar to this:

    $ python3 pure_concurrency_test.py | sort | uniq

    0
    00
    00 1 2 3 4 5 6 7
    0 0 1 2 3 4 5 6 7 8
    00 1 2 3 4 5 6 7 8
    0 1
    0 1 2
    0 1 20 1 2 3 4 5 6 7 8
    0 1 2 3
    0 1 2 3 4
    0 1 2 3 4
    0 1 2 3 4 0 1 2 3
    0 1 2 3 40 1 2 3 4 5
    0 1 2 3 4 5
    0 1 2 3 4 50 1 2 3 4 5 6
    0 1 2 3 4 5 6
    0 1 2 3 4 5 6 7
    0 1 2 3 4 5 6 7
    0 1 2 3 4 5 6 7 8
     1
    1
     1 2 3 4 5 6 7
     1 2 3 4 5 6 7 8
     3 4 5
     5
    5
     8

As we see, our pure python version of `print_list()` is also not thread-safe.
In order to fix this, the only portion of the code we have to protect is the
part that prints (just as before). Hence if we add locks into our code as
follows, we no longer see a race condition:

`pure_concurrency_test.py`
***
    from threading import Thread, Lock
    import time

    lock = Lock() # <----------------- HERE IS OUR NEW LOCK!

    def print_list(strings):
        time.sleep(1)
        with lock: # <---------------- HERE WE ACQUIRE THE LOCK!
            for s in strings:
                print(s, end=' ')
            print()

    groups = []
    for i in range(10000):
        groups.append([str(val) for val in range(i % 10)])

    threads = [Thread(target=print_list, args=(group,)) for group in groups]
    [t.start() for t in threads]
    [t.join() for t in threads]
***

If I run this I see the following:

    $ python3 pure_concurrency_test.py | sort | uniq

    0
    0 1
    0 1 2
    0 1 2 3
    0 1 2 3 4
    0 1 2 3 4 5
    0 1 2 3 4 5 6
    0 1 2 3 4 5 6 7
    0 1 2 3 4 5 6 7 8


## Conclusion <a name="conclusion"></a>

Releasing the GIL in a C extension really is not that bad. As explained
[here](https://docs.python.org/3/c-api/init.html#thread-state-and-the-global-interpreter-lock),
you need to finish making use of the python/C API (e.g. by converting all the
python objects to C objects as we did) and then release the GIL using the
provided macros. The difficulty lies the concurrent programming itself and not
in python since it is now your responsibility to be sure that your extension
has no race conditions. (Hopefully you're able to achieve this without using
such a coarse lock as to make releasing the GIL unnecessary!)

As I stated in the beginning, before you actually start writing extensions like
this, think hard as to whether it's really necessary. Don't leave the wonderful
land of Python without good reason! In any case, I hope this document is
educational and makes concurrent programming in python a little easier to
understand.
