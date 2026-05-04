# Pointer syntax

Early in development, the robot selected a leading * to indicate that a variable is a pointer to the listed type. I want this changed to the symbol `ptr` in a type expression. `foo:*Node` should become `foo:ptr:Node` (sugared) or `(foo ptr Node)` (canonical). The star syntax should be removed.

This may require an intermediate step where both are supported for bootstrap.

Breaking backward compatibility is fine an this point. Nucleus is not used for anything but its own compiler.

#### Robot

I've read the design doc and surveyed the code. The bulk of the work is mechanical (~430 occurrences of *Type syntax across src/, lib/, examples/, plus boot/nucleusc.ll's    
  bootstrapping role), but a few semantic decisions need your call before I start:
                                                                                                                                                                                
  1. Canonical shape for nested types. Desugar currently splits on : flat: foo:ptr:Node → (foo ptr Node). So the type spans two siblings of the binding form, not a sublist. Two
   options:                                                                                                                                                                     
  - (a) Flat — keep desugar as-is; teach parse-type-from-node / extract-name-and-type that within a typed-binding form, the elements after the name compose a type expression   
  where leading ptr consumes the next element as elem-type. Cheapest.                                                                                                           
  - (b) Nested — change desugar to produce (foo (ptr Node)) so the type is one node. Cleaner, but then top-level uses like (cast (ptr Node) x) and binding-form types follow the
   same rule. I'd lean this way for orthogonality. 
   
#### Designer

Use a nested form so that when the type expression is a list, all the symbols in it are describing the type. `(foo Node)`, `(foo (ptr Node)`, `(foo (ptr ptr Node)`, etc....

#### Robot
                                                                                                                                                                                
  2. ptr overload. Bare ptr is already a type meaning "opaque/void pointer" (ty-ptr). Confirm the plan is: bare ptr keeps current meaning; only (ptr T) (or ptr T in a          
  typed-binding tail under option a) constructs a typed pointer. So *ptr → ptr:ptr (pointer to opaque ptr) still works.                                                         
                                                                                                                                                                                
  3. Inline type positions — (cast *Node x), (sizeof Node), (addr-of x). With option (b) above, (cast *Node x) becomes (cast (ptr Node) x). With option (a), cast would need a  
  special multi-arg form, which is ugly — another reason to prefer (b). Confirm (cast (ptr Node) x) is the target.
                                                                                                                                                                                
  4. Bootstrap sequence. I plan to:                                                                                                                                             
  1. Teach the current compiler to accept both *Node and the new form, keeping *Node parsing intact.
  2. Rebuild boot/nucleusc.ll from that dual-support compiler.                                                                                                                  
  3. Migrate every src/, lib/, examples/, tests/ file to the new syntax.                                                                                                      
  4. Verify self-host + tests pass.                                                                                                                                             
  5. Remove *Node parsing entirely; rebuild boot/ again.                                                                                                                      
                                                                                                                                                                                
     OK to land all five steps as separate commits on stage6-cleanup? Or do you want the dual-support / removal in separate PRs?                                                
                                                                                                                                                                                
  5. After removal. Should an unmigrated *Foo produce a clear "use (ptr Foo) instead" error, or just fall through to "unknown type: *Foo"? (The first is one extra check; I'd   
  add it.) 
  
#### Designer

2. Overload `ptr`

3. We're going with B here

4. The sequence looks fine. Do all the work and I'll commit the end result.

5. No need for an extra check. Nucleus has no users at this time, so nobody will make this mistake.
