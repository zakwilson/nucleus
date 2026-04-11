## Initial toy implementation

For the initial implementation, we need to be able to compile this program:

    (include stdio)

    (defn main:int ()
      (let (i:int 1
            j:int 2)
        (while (< i 5)
          (printf "i = %d j = %d\n" i j)
          (inc! i)
          (set! j (* 2 i))))
      (return 0))
      
The program should output:

    i = 1 j = 2
    i = 2 j = 4
    i = 3 j = 6
    i = 4 j = 8
