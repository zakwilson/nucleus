# Collection types

Nucleus needs reasonable default collection types, and protocols defining the common operations on them. The types themselves should be libraries as many programs won't need , for example, a HashSet. The protocols should probably be core.

## Protocols

* Assoc
* Seq
* Set

## Functions defined in terms of protocols

### Coll

* count

### Seq

* map
* reduce
* filter
* append
* prepend
* insert
* get (index)


### Set

* union
* difference
* intersection
* select
* get (value)


### Assoc

* get (key)
* assoc

## Types

These collections should contain values with homogenous types.

These types get syntax based on reader macros. The macro should infer the type of the values and expand to a constructor.

[1 2 3] -> (Vector 'int 1 2 3)

An empty literal like [] is an error; use (Vector 'int) instead.

### Vector

A dynamically-sized sequence similar to C++ STL vector. O(1) get, append, and prepend. O(n) insert. 

### HashSet

O(1) get, insert, delete

### HashMap

O(1) get, assoc, delete
