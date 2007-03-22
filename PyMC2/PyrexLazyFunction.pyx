from numpy import array, zeros, ones, arange, resize
from PyMC2 import PyMCBase, ContainerBase

# The numpy distutils support array element access as follows:
# PyArray_GETPTR1(self.ultimate_args, 1). No need to explicitly
# include the header.

cdef extern from "stdlib.h":
    void* malloc(int size)
    
cdef extern from "numpy/ndarrayobject.h":
    void* PyArray_DATA(object obj)

cdef class LazyFunction:
    
    cdef public object arguments, fun, argument_values
    cdef object pymc_object_args, other_args
    cdef int cache_depth, N_args, 
    cdef object ultimate_args, ultimate_keys, ultimate_arg_values
    cdef void **ultimate_arg_p, **ultimate_keys_p, **ultimate_arg_value_p
    cdef object cached_args, cached_values
    cdef void **cached_arg_p
    
    def __init__(self, fun, arguments, cache_depth):
        
        cdef object arg, name
        cdef int i
        
        self.arguments = arguments
        self.cache_depth = cache_depth
        
        self.pymc_object_args = {}
        self.other_args = {}
        
        self.ultimate_args=[]
        self.ultimate_keys=[]

        self.argument_values = {}
        
        for name in arguments.iterkeys():
            arg = arguments[name]

            if isinstance(arg, ContainerBase):
                
                self.argument_values[name] = arg.value
                self.ultimate_args.append(arg)
                self.ultimate_keys.append(arg)                
                
                for obj in arg.pymc_objects:
                    self.ultimate_args.append(obj)
                    self.ultimate_keys.append(None)
                
            elif isinstance(arg, PyMCBase):
                self.pymc_object_args[name] = arg
                self.ultimate_args.append(arg)
                self.ultimate_keys.append(name)
                self.argument_values[name] = arg.value
                
            else:
                self.other_args[name] = arg
                self.argument_values[name] = arg
                
        self.ultimate_args = array(self.ultimate_args, dtype=object)
        self.ultimate_keys = array(self.ultimate_keys, dtype=object)
                
        self.N_args = len(self.ultimate_args)
        
        self.ultimate_arg_values = zeros(self.N_args, dtype=object)
        self.cached_args = zeros(self.cache_depth * self.N_args, dtype=object)
        self.cached_values = []
        for i in range(self.cache_depth):
            self.cached_values.append(None)
        
        self.ultimate_arg_values[:] = None
        self.cached_args[:] = None

        self.fun = fun
        
        self.get_array_data()
    
    
    cdef void get_array_data(self):
        self.ultimate_arg_p = <void**> PyArray_DATA(self.ultimate_args)
        self.ultimate_keys_p = <void**> PyArray_DATA(self.ultimate_keys)
        self.ultimate_arg_value_p = <void**> PyArray_DATA(self.ultimate_arg_values)
        self.cached_arg_p = <void**> PyArray_DATA(self.cached_args)
        
        
        
    
    # See if a recompute is necessary.
    cdef int check_argument_caches(self):
        cdef int i, j, mismatch

        for i from 0 <= i < self.cache_depth:
            mismatch = 0
            
            for j from 0 <= j < self.N_args:
                if not self.ultimate_arg_value_p[j] == self.cached_arg_p[i * self.N_args + j]:
                    mismatch = 1
                    break
                    
            if mismatch == 0:
                return i        

        return -1;

    # Extract the values of arguments that are PyMC objects or containers.
    # Don't worry about unpacking the containers, see their value attribute.
    def refresh_argument_values(self):

        cdef object item
        cdef int i
        cdef void* name
        
        for i from 0 <= i < self.N_args:
            item = (<object> self.ultimate_arg_p[i]).value
            self.ultimate_arg_value_p[i] = <void*> item

            name = self.ultimate_keys_p[i]
            if not name == <void*> None:
                self.argument_values[<object> name] = item
            
        
        
        
    cdef void cache(self, value):
        cdef int i, j
        
        self.cached_values.pop()
        self.cached_values.insert(0,value)
        
        # Push back
        for i from 0 <= i < self.cache_depth - 1:
            for j from 0 <= j < self.N_args:
                self.cached_arg_p[(i+1) * self.N_args + j] = self.cached_arg_p[i * self.N_args + j]
        
        # Store new
        for j from 0 <= j < self.N_args:
            self.cached_arg_p[j] = self.ultimate_arg_value_p[j]
        

    def get(self):
        
        cdef int match_index
        
        self.refresh_argument_values()
        match_index = self.check_argument_caches()

        if match_index < 0:

            #Recompute
            value = self.fun(**self.argument_values)

            self.cache(value)
        
        else: value = <object> self.cached_values[match_index]

        return value