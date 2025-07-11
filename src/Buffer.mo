/// Class `Buffer<X>` provides a mutable list of elements of type `X`.
/// It wraps a resizable underlying array and is comparable to `ArrayList` or `Vector` in other languages.
///
/// You can convert a buffer to a fixed-size array using `Buffer.toArray`, which is recommended for storing data in stable variables.
///
/// Like arrays, buffer elements are indexed from `0` to `size - 1`.
///
/// :::note Assumptions
///
/// Runtime and space complexity assumes that `combine`, `equal`, and other functions execute in `O(1)` time and space.
///
/// :::
///
/// :::note Size vs capacity
///
/// - `size`: Number of elements in the buffer.
/// - `capacity`: Length of the underlying array.
///
/// The invariant `capacity >= size` always holds.
/// :::
///
/// :::warning Performance caveat
///
/// Operations like `add` are amortized `O(1)` but can take `O(n)` in the worst case.
/// For large buffers, these worst cases may exceed the cycle limit per message.
/// Use with care when growing buffers dynamically.
/// :::
///
/// :::info Constructor behavior
///
/// The `initCapacity` argument sets the initial capacity of the underlying array.
///
/// - When the capacity is exceeded, the array grows by a factor of 1.5.
/// - When the buffer size drops below 1/4 of the capacity, it shrinks by a factor of 2.
/// :::
///
/// Example:
///
/// ```motoko name=initialize
/// import Buffer "mo:base/Buffer";
///
/// let buffer = Buffer.Buffer<Nat>(3); // Creates a new Buffer
/// ```
///
/// | Runtime   | Space     |
/// |-----------|-----------|
/// | `O(initCapacity)` | `O(initCapacity)` |

import Prim "mo:⛔";
import Result "Result";
import Order "Order";
import Array "Array";

module {
  type Order = Order.Order;

  // The following constants are used to manage the capacity.
  // The length of `elements` is increased by `INCREASE_FACTOR` when capacity is reached.
  // The length of `elements` is decreased by `DECREASE_FACTOR` when capacity is strictly less than
  // `DECREASE_THRESHOLD`.

  // INCREASE_FACTOR = INCREASE_FACTOR_NUME / INCREASE_FACTOR_DENOM (with floating point division)
  // Keep INCREASE_FACTOR low to minimize cycle limit problem
  private let INCREASE_FACTOR_NUME = 3;
  private let INCREASE_FACTOR_DENOM = 2;
  private let DECREASE_THRESHOLD = 4; // Don't decrease capacity too early to avoid thrashing
  private let DECREASE_FACTOR = 2;
  private let DEFAULT_CAPACITY = 8;

  private func newCapacity(oldCapacity : Nat) : Nat {
    if (oldCapacity == 0) {
      1
    } else {
      // calculates ceil(oldCapacity * INCREASE_FACTOR) without floats
      ((oldCapacity * INCREASE_FACTOR_NUME) + INCREASE_FACTOR_DENOM - 1) / INCREASE_FACTOR_DENOM
    }
  };

  public class Buffer<X>(initCapacity : Nat) = this {
    var _size : Nat = 0; // avoid name clash with `size()` method
    var elements : [var ?X] = Prim.Array_init(initCapacity, null);

    /// Returns the current number of elements in the buffer.
    ///
    /// Example:
    ///
    /// ```motoko include=initialize
    /// buffer.size() // => 0
    /// ```
    ///
    /// | Runtime   | Space     |
    /// |-----------|-----------|
    /// | `O(1)` | `O(1)` |
    public func size() : Nat = _size;

    /// Adds a single element to the end of the buffer, doubling
    /// the size of the array if capacity is exceeded.
    ///
    /// Example:
    ///
    /// ```motoko include=initialize
    /// buffer.add(0); // add 0 to buffer
    /// buffer.add(1);
    /// buffer.add(2);
    /// buffer.add(3); // causes underlying array to increase in capacity
    /// Buffer.toArray(buffer) // => [0, 1, 2, 3]
    /// ```
    ///
    /// | Runtime (worst) | Runtime (amortized) | Space (worst) | Space (amortized) |
    /// |------------------|----------------------|----------------|---------------------|
    /// | `O(size)`           | `O(1)`               | `O(size)`         | `O(1)`              |
    public func add(element : X) {
      if (_size == elements.size()) {
        reserve(newCapacity(elements.size()))
      };
      elements[_size] := ?element;
      _size += 1
    };

    /// Returns the element at index `index`. Traps if  `index >= size`. Indexing is zero-based.
    ///
    /// Example:
    ///
    /// ```motoko include=initialize
    /// buffer.add(10);
    /// buffer.add(11);
    /// buffer.get(0); // => 10
    /// ```
    ///
    /// | Runtime   | Space     |
    /// |-----------|-----------|
    /// | `O(1)` | `O(1)` |
    public func get(index : Nat) : X {
      switch (elements[index]) {
        case (?element) element;
        case null Prim.trap("Buffer index out of bounds in get")
      }
    };

    /// Returns the element at index `index` as an option.
    /// Returns `null` when `index >= size`. Indexing is zero-based.
    ///
    /// Example:
    ///
    /// ```motoko include=initialize
    /// buffer.add(10);
    /// buffer.add(11);
    /// let x = buffer.getOpt(0); // => ?10
    /// let y = buffer.getOpt(2); // => null
    /// ```
    ///
    /// | Runtime   | Space     |
    /// |-----------|-----------|
    /// | `O(1)` | `O(1)` |


    public func getOpt(index : Nat) : ?X {
      if (index < _size) {
        elements[index]
      } else {
        null
      }
    };
    /// ```motoko include=initialize
    /// buffer.add(10);
    /// buffer.put(0, 20); // overwrites 10 at index 0 with 20
    /// Buffer.toArray(buffer) // => [20]
    /// ```
    ///
    /// | Runtime   | Space     |
    /// |-----------|-----------|
    /// | `O(1)` | `O(1)` |
    ///
    public func put(index : Nat, element : X) {
      if (index >= _size) {
        Prim.trap "Buffer index out of bounds in put"
      };
      elements[index] := ?element
    };

    /// Removes and returns the last item in the buffer or `null` if
    /// the buffer is empty.
    ///
    /// Example:
    ///
    /// ```motoko include=initialize
    /// buffer.add(10);
    /// buffer.add(11);
    /// buffer.removeLast(); // => ?11
    /// ```
    ///
    /// | Runtime (worst) | Runtime (amortized) | Space (worst) | Space (amortized) |
    /// |------------------|----------------------|----------------|---------------------|
    /// | `O(size)`           | `O(1)`               | `O(size)`         | `O(1)`              |
    ///
    public func removeLast() : ?X {
      if (_size == 0) {
        return null
      };

      _size -= 1;
      let lastElement = elements[_size];
      elements[_size] := null;

      if (_size < elements.size() / DECREASE_THRESHOLD) {
        // FIXME should this new capacity be a function of _size
        // instead of the current capacity? E.g. _size * INCREASE_FACTOR
        reserve(elements.size() / DECREASE_FACTOR)
      };

      lastElement
    };

    /// Removes and returns the element at `index` from the buffer.
    /// All elements with index > `index` are shifted one position to the left.
    /// This may cause a downsizing of the array.
    ///
    /// Traps if index >= size.
    ///
    /// :::warning Inefficient pattern
    ///
    /// Repeated removal of elements using this method is inefficient and may indicate that a different data structure would better suit your use case.
    /// :::
    ///
    /// Example:
    ///
    /// ```motoko include=initialize
    /// buffer.add(10);
    /// buffer.add(11);
    /// buffer.add(12);
    /// let x = buffer.remove(1); // evaluates to 11. 11 no longer in list.
    /// Buffer.toArray(buffer) // => [10, 12]
    /// ```
    ///
    /// | Runtime (worst) | Runtime (amortized) | Space (worst) | Space (amortized) |
    /// |------------------|----------------------|----------------|---------------------|
    /// | `O(size)`           |-               | `O(size)`         | `O(1)`              |
    public func remove(index : Nat) : X {
      if (index >= _size) {
        Prim.trap "Buffer index out of bounds in remove"
      };

      let element = elements[index];

      // copy elements to new array and shift over in one pass
      if ((_size - 1) : Nat < elements.size() / DECREASE_THRESHOLD) {
        let elements2 = Prim.Array_init<?X>(elements.size() / DECREASE_FACTOR, null);

        var i = 0;
        var j = 0;
        label l while (i < _size) {
          if (i == index) {
            i += 1;
            continue l
          };

          elements2[j] := elements[i];
          i += 1;
          j += 1
        };
        elements := elements2
      } else {
        // just shift over elements
        var i = index;
        while (i < (_size - 1 : Nat)) {
          elements[i] := elements[i + 1];
          i += 1
        };
        elements[_size - 1] := null
      };

      _size -= 1;

      switch (element) {
        case (?element) {
          element
        };
        case null {
          Prim.trap "Malformed buffer in remove"
        }
      }
    };

    /// Resets the buffer. Capacity is set to 8.
    ///
    /// Example:
    ///
    /// ```motoko include=initialize
    /// buffer.add(10);
    /// buffer.add(11);
    /// buffer.add(12);
    /// buffer.clear(); // buffer is now empty
    /// Buffer.toArray(buffer) // => []
    /// ```
    ///
    /// | Runtime   | Space     |
    /// |-----------|-----------|
    /// | `O(1)` | `O(1)` |
    public func clear() {
      _size := 0;
      reserve(DEFAULT_CAPACITY)
    };

    /// Removes all elements from the buffer for which the predicate returns false.
    /// The predicate is given both the index of the element and the element itself.
    /// This may cause a downsizing of the array.
    ///
    /// Example:
    ///
    /// ```motoko include=initialize
    /// buffer.add(10);
    /// buffer.add(11);
    /// buffer.add(12);
    /// buffer.filterEntries(func(_, x) = x % 2 == 0); // only keep even elements
    /// Buffer.toArray(buffer) // => [10, 12]
    /// ```
    ///
    /// | Runtime (worst) | Runtime (amortized) | Space (worst) | Space (amortized) |
    /// |------------------|----------------------|----------------|---------------------|
    /// | `O(size)`           | -               | `O(size)`         | `O(1)`              |
    ///
    public func filterEntries(predicate : (Nat, X) -> Bool) {
      var numRemoved = 0;
      let keep = Prim.Array_tabulate<Bool>(
        _size,
        func i {
          switch (elements[i]) {
            case (?element) {
              if (predicate(i, element)) {
                true
              } else {
                numRemoved += 1;
                false
              }
            };
            case null {
              Prim.trap "Malformed buffer in filter()"
            }
          }
        }
      );

      let capacity = elements.size();

      if ((_size - numRemoved : Nat) < capacity / DECREASE_THRESHOLD) {
        let elements2 = Prim.Array_init<?X>(capacity / DECREASE_FACTOR, null);

        var i = 0;
        var j = 0;
        while (i < _size) {
          if (keep[i]) {
            elements2[j] := elements[i];
            i += 1;
            j += 1
          } else {
            i += 1
          }
        };

        elements := elements2
      } else {
        var i = 0;
        var j = 0;
        while (i < _size) {
          if (keep[i]) {
            elements[j] := elements[i];
            i += 1;
            j += 1
          } else {
            i += 1
          }
        };

        while (j < _size) {
          elements[j] := null;
          j += 1
        }
      };

      _size -= numRemoved
    };

    /// Returns the capacity of the buffer (the length of the underlying array).
    ///
    /// Example:
    ///
    /// ```motoko include=initialize
    /// let buffer = Buffer.Buffer<Nat>(2); // underlying array has capacity 2
    /// buffer.add(10);
    /// let c1 = buffer.capacity(); // => 2
    /// buffer.add(11);
    /// buffer.add(12); // causes capacity to increase by factor of 1.5
    /// let c2 = buffer.capacity(); // => 3
    /// ```
    ///
    /// | Runtime   | Space     |
    /// |-----------|-----------|
    /// | `O(1)` | `O(1)` |
    public func capacity() : Nat = elements.size();

    /// Changes the capacity to `capacity`. Traps if `capacity` < `size`.
    ///
    /// ```motoko include=initialize
    /// buffer.reserve(4);
    /// buffer.add(10);
    /// buffer.add(11);
    /// buffer.capacity(); // => 4
    /// ```
    ///
    /// | Runtime   | Space     |
    /// |-----------|-----------|
    /// | `O(capacity)` | `O(capacity)` |
    public func reserve(capacity : Nat) {
      if (capacity < _size) {
        Prim.trap "capacity must be >= size in reserve"
      };

      let elements2 = Prim.Array_init<?X>(capacity, null);

      var i = 0;
      while (i < _size) {
        elements2[i] := elements[i];
        i += 1
      };
      elements := elements2
    };

    /// Adds all elements in buffer `b` to this buffer.
    ///
    /// ```motoko include=initialize
    /// let buffer1 = Buffer.Buffer<Nat>(2);
    /// let buffer2 = Buffer.Buffer<Nat>(2);
    /// buffer1.add(10);
    /// buffer1.add(11);
    /// buffer2.add(12);
    /// buffer2.add(13);
    /// buffer1.append(buffer2); // adds elements from buffer2 to buffer1
    /// Buffer.toArray(buffer1) // => [10, 11, 12, 13]
    /// ```
    ///
    /// | Runtime (worst) | Runtime (amortized) | Space (worst) | Space (amortized) |
    /// |------------------|----------------------|----------------|---------------------|
    /// | `O(size1 + size2)`           | `O(size2)`              | `O(size1 +size2)`         | `O(1)`              |

    public func append(buffer2 : Buffer<X>) {
      let size2 = buffer2.size();
      // Make sure you only allocate a new array at most once
      if (_size + size2 > elements.size()) {
        // FIXME would be nice to have a tabulate for var arrays here
        reserve(newCapacity(_size + size2))
      };
      var i = 0;
      while (i < size2) {
        elements[_size + i] := buffer2.getOpt i;
        i += 1
      };

      _size += size2
    };

    /// Inserts `element` at `index`, shifts all elements to the right of
    /// `index` over by one index. Traps if `index` is greater than size.
    ///
    /// ```motoko include=initialize
    /// let buffer1 = Buffer.Buffer<Nat>(2);
    /// let buffer2 = Buffer.Buffer<Nat>(2);
    /// buffer.add(10);
    /// buffer.add(11);
    /// buffer.insert(1, 9);
    /// Buffer.toArray(buffer) // => [10, 9, 11]
    /// ```
    ///
    /// | Runtime (worst) | Runtime (amortized) | Space (worst) | Space (amortized) |
    /// |------------------|----------------------|----------------|---------------------|
    /// | `O(size)`           | -               | `O(size)`         | `O(1)`              |
    public func insert(index : Nat, element : X) {
      if (index > _size) {
        Prim.trap "Buffer index out of bounds in insert"
      };
      let capacity = elements.size();

      if (_size + 1 > capacity) {
        let capacity = elements.size();
        let elements2 = Prim.Array_init<?X>(newCapacity capacity, null);
        var i = 0;
        while (i < _size + 1) {
          if (i < index) {
            elements2[i] := elements[i]
          } else if (i == index) {
            elements2[i] := ?element
          } else {
            elements2[i] := elements[i - 1]
          };

          i += 1
        };
        elements := elements2
      } else {
        var i : Nat = _size;
        while (i > index) {
          elements[i] := elements[i - 1];
          i -= 1
        };
        elements[index] := ?element
      };

      _size += 1
    };

    /// Inserts `buffer2` at `index`, and shifts all elements to the right of
    /// `index` over by size2. Traps if `index` is greater than size.
    ///
    /// ```motoko include=initialize
    /// let buffer1 = Buffer.Buffer<Nat>(2);
    /// let buffer2 = Buffer.Buffer<Nat>(2);
    /// buffer1.add(10);
    /// buffer1.add(11);
    /// buffer2.add(12);
    /// buffer2.add(13);
    /// buffer1.insertBuffer(1, buffer2);
    /// Buffer.toArray(buffer1) // => [10, 12, 13, 11]
    /// ```
    ///
    /// | Runtime (worst) | Runtime (amortized) | Space (worst) | Space (amortized) |
    /// |------------------|----------------------|----------------|---------------------|
    /// | `O(size)`           | -             | `O(size1 +size2)`         | `O(1)`              |
    public func insertBuffer(index : Nat, buffer2 : Buffer<X>) {
      if (index > _size) {
        Prim.trap "Buffer index out of bounds in insertBuffer"
      };

      let size2 = buffer2.size();
      let capacity = elements.size();

      // copy elements to new array and shift over in one pass
      if (_size + size2 > capacity) {
        let elements2 = Prim.Array_init<?X>(newCapacity(_size + size2), null);
        var i = 0;
        for (element in elements.vals()) {
          if (i == index) {
            i += size2
          };
          elements2[i] := element;
          i += 1
        };

        i := 0;
        while (i < size2) {
          elements2[i + index] := buffer2.getOpt(i);
          i += 1
        };
        elements := elements2
      } // just insert
      else {
        var i = index;
        while (i < index + size2) {
          if (i < _size) {
            elements[i + size2] := elements[i]
          };
          elements[i] := buffer2.getOpt(i - index);

          i += 1
        }
      };

      _size += size2
    };

    /// Sorts the elements in the buffer according to `compare`.
    /// Sort is deterministic, stable, and in-place.
    ///
    /// ```motoko include=initialize
    /// import Nat "mo:base/Nat";
    ///
    /// buffer.add(11);
    /// buffer.add(12);
    /// buffer.add(10);
    /// buffer.sort(Nat.compare);
    /// Buffer.toArray(buffer) // => [10, 11, 12]
    /// ```
    ///
    /// | Runtime   | Space     |
    /// |-----------|-----------|
    /// | `O(size * log(size))` | `O(size)` |
    public func sort(compare : (X, X) -> Order.Order) {
      // Stable merge sort in a bottom-up iterative style
      if (_size == 0) {
        return
      };
      let scratchSpace = Prim.Array_init<?X>(_size, null);

      let sizeDec = _size - 1 : Nat;
      var currSize = 1; // current size of the subarrays being merged
      // when the current size == size, the array has been merged into a single sorted array
      while (currSize < _size) {
        var leftStart = 0; // selects the current left subarray being merged
        while (leftStart < sizeDec) {
          let mid : Nat = if (leftStart + currSize - 1 : Nat < sizeDec) {
            leftStart + currSize - 1
          } else { sizeDec };
          let rightEnd : Nat = if (leftStart + (2 * currSize) - 1 : Nat < sizeDec) {
            leftStart + (2 * currSize) - 1
          } else { sizeDec };

          // Merge subarrays elements[leftStart...mid] and elements[mid+1...rightEnd]
          var left = leftStart;
          var right = mid + 1;
          var nextSorted = leftStart;
          while (left < mid + 1 and right < rightEnd + 1) {
            let leftOpt = elements[left];
            let rightOpt = elements[right];
            switch (leftOpt, rightOpt) {
              case (?leftElement, ?rightElement) {
                switch (compare(leftElement, rightElement)) {
                  case (#less or #equal) {
                    scratchSpace[nextSorted] := leftOpt;
                    left += 1
                  };
                  case (#greater) {
                    scratchSpace[nextSorted] := rightOpt;
                    right += 1
                  }
                }
              };
              case (_, _) {
                // only sorting non-null items
                Prim.trap "Malformed buffer in sort"
              }
            };
            nextSorted += 1
          };
          while (left < mid + 1) {
            scratchSpace[nextSorted] := elements[left];
            nextSorted += 1;
            left += 1
          };
          while (right < rightEnd + 1) {
            scratchSpace[nextSorted] := elements[right];
            nextSorted += 1;
            right += 1
          };

          // Copy over merged elements
          var i = leftStart;
          while (i < rightEnd + 1) {
            elements[i] := scratchSpace[i];
            i += 1
          };

          leftStart += 2 * currSize
        };
        currSize *= 2
      }
    };

    /// Returns an Iterator (`Iter`) over the elements of this buffer.
    /// Iterator provides a single method `next()`, which returns
    /// elements in order, or `null` when out of elements to iterate over.
    ///
    /// ```motoko include=initialize
    /// buffer.add(10);
    /// buffer.add(11);
    /// buffer.add(12);
    ///
    /// var sum = 0;
    /// for (element in buffer.vals()) {
    ///  sum += element;
    /// };
    /// sum // => 33
    /// ```
    ///
    /// | Runtime   | Space     |
    /// |-----------|-----------|
    /// | `O(1)` | `O(1)` |
    public func vals() : { next : () -> ?X } = object {
      // FIXME either handle modification to underlying list
      // or explicitly warn users in documentation
      var nextIndex = 0;
      public func next() : ?X {
        if (nextIndex >= _size) {
          return null
        };
        let nextElement = elements[nextIndex];
        nextIndex += 1;
        nextElement
      }
    };

    // FOLLOWING METHODS ARE DEPRECATED

    /// @deprecated Use the static library function instead of this instance method.
    public func clone() : Buffer<X> {
      let newBuffer = Buffer<X>(elements.size());
      for (element in vals()) {
        newBuffer.add(element)
      };
      newBuffer
    };

    /// @deprecated Use the static library function instead of this instance method.
    public func toArray() : [X] =
    // immutable clone of array
    Prim.Array_tabulate<X>(
      _size,
      func(i : Nat) : X { get i }
    );

    /// @deprecated Use the static library function instead of this instance method.
    public func toVarArray() : [var X] {
      if (_size == 0) { [var] } else {
        let newArray = Prim.Array_init<X>(_size, get 0);
        var i = 0;
        for (element in vals()) {
          newArray[i] := element;
          i += 1
        };
        newArray
      }
    }
  };

  /// Returns true if and only if the buffer is empty.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// buffer.add(2);
  /// buffer.add(0);
  /// buffer.add(3);
  /// Buffer.isEmpty(buffer); // => false
  /// ```
  ///
  /// ```motoko include=initialize
  /// Buffer.isEmpty(buffer); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(1)` | `O(1)` |
  public func isEmpty<X>(buffer : Buffer<X>) : Bool = buffer.size() == 0;

  /// Returns true if `buffer` contains `element` with respect to equality
  /// defined by `equal`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(2);
  /// buffer.add(0);
  /// buffer.add(3);
  /// Buffer.contains<Nat>(buffer, 2, Nat.equal); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func contains<X>(buffer : Buffer<X>, element : X, equal : (X, X) -> Bool) : Bool {
    for (current in buffer.vals()) {
      if (equal(current, element)) {
        return true
      }
    };

    false
  };

  /// Returns a copy of `buffer`, with the same capacity.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// buffer.add(1);
  ///
  /// let clone = Buffer.clone(buffer);
  /// Buffer.toArray(clone); // => [1]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func clone<X>(buffer : Buffer<X>) : Buffer<X> {
    let newBuffer = Buffer<X>(buffer.capacity());
    for (element in buffer.vals()) {
      newBuffer.add(element)
    };
    newBuffer
  };

  /// Finds the greatest element in `buffer` defined by `compare`.
  /// Returns `null` if `buffer` is empty.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  ///
  /// Buffer.max(buffer, Nat.compare); // => ?2
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func max<X>(buffer : Buffer<X>, compare : (X, X) -> Order) : ?X {
    if (buffer.size() == 0) {
      return null
    };

    var maxSoFar = buffer.get(0);
    for (current in buffer.vals()) {
      switch (compare(current, maxSoFar)) {
        case (#greater) {
          maxSoFar := current
        };
        case _ {}
      }
    };

    ?maxSoFar
  };

  /// Finds the least element in `buffer` defined by `compare`.
  /// Returns `null` if `buffer` is empty.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  ///
  /// Buffer.min(buffer, Nat.compare); // => ?1
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func min<X>(buffer : Buffer<X>, compare : (X, X) -> Order) : ?X {
    if (buffer.size() == 0) {
      return null
    };

    var minSoFar = buffer.get(0);
    for (current in buffer.vals()) {
      switch (compare(current, minSoFar)) {
        case (#less) {
          minSoFar := current
        };
        case _ {}
      }
    };

    ?minSoFar
  };

  /// Defines equality for two buffers, using `equal` to recursively compare elements in the
  /// buffers. Returns true if the two buffers are of the same size, and `equal`
  /// evaluates to true for every pair of elements in the two buffers of the same
  /// index.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let buffer1 = Buffer.Buffer<Nat>(2);
  /// buffer1.add(1);
  /// buffer1.add(2);
  ///
  /// let buffer2 = Buffer.Buffer<Nat>(5);
  /// buffer2.add(1);
  /// buffer2.add(2);
  ///
  /// Buffer.equal(buffer1, buffer2, Nat.equal); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func equal<X>(buffer1 : Buffer<X>, buffer2 : Buffer<X>, equal : (X, X) -> Bool) : Bool {
    let size1 = buffer1.size();

    if (size1 != buffer2.size()) {
      return false
    };

    var i = 0;
    while (i < size1) {
      if (not equal(buffer1.get(i), buffer2.get(i))) {
        return false
      };
      i += 1
    };

    true
  };

  /// Defines comparison for two buffers, using `compare` to recursively compare elements in the
  /// buffers. Comparison is defined lexicographically.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let buffer1 = Buffer.Buffer<Nat>(2);
  /// buffer1.add(1);
  /// buffer1.add(2);
  ///
  /// let buffer2 = Buffer.Buffer<Nat>(3);
  /// buffer2.add(3);
  /// buffer2.add(4);
  ///
  /// Buffer.compare<Nat>(buffer1, buffer2, Nat.compare); // => #less
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func compare<X>(buffer1 : Buffer<X>, buffer2 : Buffer<X>, compare : (X, X) -> Order.Order) : Order.Order {
    let size1 = buffer1.size();
    let size2 = buffer2.size();
    let minSize = if (size1 < size2) { size1 } else { size2 };

    var i = 0;
    while (i < minSize) {
      switch (compare(buffer1.get(i), buffer2.get(i))) {
        case (#less) {
          return #less
        };
        case (#greater) {
          return #greater
        };
        case _ {}
      };
      i += 1
    };

    if (size1 < size2) {
      #less
    } else if (size1 == size2) {
      #equal
    } else {
      #greater
    }
  };

  /// Creates a textual representation of `buffer`, using `toText` to recursively
  /// convert the elements into Text.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  /// buffer.add(4);
  ///
  /// Buffer.toText(buffer, Nat.toText); // => "[1, 2, 3, 4]"
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |

  public func toText<X>(buffer : Buffer<X>, toText : X -> Text) : Text {
    let size : Int = buffer.size();
    var i = 0;
    var text = "";
    while (i < size - 1) {
      text := text # toText(buffer.get(i)) # ", "; // Text implemented as rope
      i += 1
    };
    if (size > 0) {
      // avoid the trailing comma
      text := text # toText(buffer.get(i))
    };

    "[" # text # "]"
  };

  /// Hashes `buffer` using `hash` to hash the underlying elements.
  /// The deterministic hash function is a function of the elements in the `buffer`, as well
  /// as their ordering.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Hash "mo:base/Hash";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  /// buffer.add(1000);
  ///
  /// Buffer.hash<Nat>(buffer, Hash.hash); // => 2_872_640_342
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func hash<X>(buffer : Buffer<X>, hash : X -> Nat32) : Nat32 {
    let size = buffer.size();
    var i = 0;
    var accHash : Nat32 = 0;

    while (i < size) {
      accHash := Prim.intToNat32Wrap(i) ^ accHash ^ hash(buffer.get(i));
      i += 1
    };

    accHash
  };

  /// Finds the first index of `element` in `buffer` using equality of elements defined
  /// by `equal`. Returns `null` if `element` is not found.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  /// buffer.add(4);
  ///
  /// Buffer.indexOf<Nat>(3, buffer, Nat.equal); // => ?2
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func indexOf<X>(element : X, buffer : Buffer<X>, equal : (X, X) -> Bool) : ?Nat {
    let size = buffer.size();
    var i = 0;
    while (i < size) {
      if (equal(buffer.get(i), element)) {
        return ?i
      };
      i += 1
    };

    null
  };

  /// Finds the last index of `element` in `buffer` using equality of elements defined
  /// by `equal`. Returns `null` if `element` is not found.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  /// buffer.add(4);
  /// buffer.add(2);
  /// buffer.add(2);
  ///
  /// Buffer.lastIndexOf<Nat>(2, buffer, Nat.equal); // => ?5
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func lastIndexOf<X>(element : X, buffer : Buffer<X>, equal : (X, X) -> Bool) : ?Nat {
    let size = buffer.size();
    if (size == 0) {
      return null
    };
    var i = size;
    while (i >= 1) {
      i -= 1;
      if (equal(buffer.get(i), element)) {
        return ?i
      }
    };

    null
  };

  /// Searches for `subBuffer` in `buffer`, and returns the starting index if it is found.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  /// buffer.add(4);
  /// buffer.add(5);
  /// buffer.add(6);
  ///
  /// let sub = Buffer.Buffer<Nat>(2);
  /// sub.add(4);
  /// sub.add(5);
  /// sub.add(6);
  ///
  /// Buffer.indexOfBuffer<Nat>(sub, buffer, Nat.equal); // => ?3
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size of buffer + size of subBuffer)` | `O(size of subBuffer)` |
  public func indexOfBuffer<X>(subBuffer : Buffer<X>, buffer : Buffer<X>, equal : (X, X) -> Bool) : ?Nat {
    // Uses the KMP substring search algorithm
    // Implementation from: https://www.educative.io/answers/what-is-the-knuth-morris-pratt-algorithm
    let size = buffer.size();
    let subSize = subBuffer.size();
    if (subSize > size or subSize == 0) {
      return null
    };

    // precompute lps
    let lps = Prim.Array_init<Nat>(subSize, 0);
    var i = 0;
    var j = 1;

    while (j < subSize) {
      if (equal(subBuffer.get(i), subBuffer.get(j))) {
        i += 1;
        lps[j] := i;
        j += 1
      } else if (i == 0) {
        lps[j] := 0;
        j += 1
      } else {
        i := lps[i - 1]
      }
    };

    // start search
    i := 0;
    j := 0;
    let subSizeDec = subSize - 1 : Nat; // hoisting loop invariant
    while (i < subSize and j < size) {
      if (equal(subBuffer.get(i), buffer.get(j)) and i == subSizeDec) {
        return ?(j - i)
      } else if (equal(subBuffer.get(i), buffer.get(j))) {
        i += 1;
        j += 1
      } else {
        if (i != 0) {
          i := lps[i - 1]
        } else {
          j += 1
        }
      }
    };

    null
  };

  /// Similar to `indexOf`, but runs in logarithmic time. Assumes that `buffer` is sorted.
  /// Behavior is undefined if `buffer` is not sorted. Uses `compare` to
  /// perform the search. Returns an index of `element` if it is found.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(4);
  /// buffer.add(5);
  /// buffer.add(6);
  ///
  /// Buffer.binarySearch<Nat>(5, buffer, Nat.compare); // => ?2
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(log(size))` | `O(1)` |
  public func binarySearch<X>(element : X, buffer : Buffer<X>, compare : (X, X) -> Order.Order) : ?Nat {
    var low = 0;
    var high = buffer.size();

    while (low < high) {
      let mid = (low + high) / 2;
      let current = buffer.get(mid);
      switch (compare(element, current)) {
        case (#equal) {
          return ?mid
        };
        case (#less) {
          high := mid
        };
        case (#greater) {
          low := mid + 1
        }
      }
    };

    null
  };

  /// Returns the sub-buffer of `buffer` starting at index `start`
  /// of length `length`. Traps if `start` is out of bounds, or `start + length`
  /// is greater than the size of `buffer`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  /// buffer.add(4);
  /// buffer.add(5);
  /// buffer.add(6);
  ///
  /// let sub = Buffer.subBuffer(buffer, 3, 2);
  /// Buffer.toText(sub, Nat.toText); // => [4, 5]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(length)` | `O(length)` |
  public func subBuffer<X>(buffer : Buffer<X>, start : Nat, length : Nat) : Buffer<X> {
    let size = buffer.size();
    let end = start + length; // exclusive
    if (start >= size or end > size) {
      Prim.trap "Buffer index out of bounds in subBuffer"
    };

    let newBuffer = Buffer<X>(newCapacity length);

    var i = start;
    while (i < end) {
      newBuffer.add(buffer.get(i));

      i += 1
    };

    newBuffer
  };

  /// Checks if `subBuffer` is a sub-Buffer of `buffer`. Uses `equal` to
  /// compare elements.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  /// buffer.add(4);
  /// buffer.add(5);
  /// buffer.add(6);
  ///
  /// let sub = Buffer.Buffer<Nat>(2);
  /// sub.add(2);
  /// sub.add(3);
  /// Buffer.isSubBufferOf(sub, buffer, Nat.equal); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size of subBuffer + size of buffer)` | `O(size of subBuffer)` |
  public func isSubBufferOf<X>(subBuffer : Buffer<X>, buffer : Buffer<X>, equal : (X, X) -> Bool) : Bool {
    switch (indexOfBuffer(subBuffer, buffer, equal)) {
      case null subBuffer.size() == 0;
      case _ true
    }
  };

  /// Checks if `subBuffer` is a strict subBuffer of `buffer`, i.e. `subBuffer` must be
  /// strictly contained inside both the first and last indices of `buffer`.
  /// Uses `equal` to compare elements.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  /// buffer.add(4);
  ///
  /// let sub = Buffer.Buffer<Nat>(2);
  /// sub.add(2);
  /// sub.add(3);
  /// Buffer.isStrictSubBufferOf(sub, buffer, Nat.equal); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size of subBuffer + size of buffer)` | `O(size of subBuffer)` |
  public func isStrictSubBufferOf<X>(subBuffer : Buffer<X>, buffer : Buffer<X>, equal : (X, X) -> Bool) : Bool {
    let subBufferSize = subBuffer.size();

    switch (indexOfBuffer(subBuffer, buffer, equal)) {
      case (?index) {
        index != 0 and index != (buffer.size() - subBufferSize : Nat) // enforce strictness
      };
      case null {
        subBufferSize == 0 and subBufferSize != buffer.size()
      }
    }
  };

  /// Returns the prefix of `buffer` of length `length`. Traps if `length`
  /// is greater than the size of `buffer`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  /// buffer.add(4);
  ///
  /// let pre = Buffer.prefix(buffer, 3); // => [1, 2, 3]
  /// Buffer.toText(pre, Nat.toText);
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(length)` | `O(length)` |
  ///
  public func prefix<X>(buffer : Buffer<X>, length : Nat) : Buffer<X> {
    let size = buffer.size();
    if (length > size) {
      Prim.trap "Buffer index out of bounds in prefix"
    };

    let newBuffer = Buffer<X>(newCapacity length);

    var i = 0;
    while (i < length) {
      newBuffer.add(buffer.get(i));
      i += 1
    };

    newBuffer
  };

  /// Checks if `prefix` is a prefix of `buffer`. Uses `equal` to
  /// compare elements.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  /// buffer.add(4);
  ///
  /// let pre = Buffer.Buffer<Nat>(2);
  /// pre.add(1);
  /// pre.add(2);
  /// Buffer.isPrefixOf(pre, buffer, Nat.equal); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size of prefix)` | `O(size of prefix)` |
  public func isPrefixOf<X>(prefix : Buffer<X>, buffer : Buffer<X>, equal : (X, X) -> Bool) : Bool {
    let sizePrefix = prefix.size();
    if (buffer.size() < sizePrefix) {
      return false
    };

    var i = 0;
    while (i < sizePrefix) {
      if (not equal(buffer.get(i), prefix.get(i))) {
        return false
      };

      i += 1
    };

    return true
  };

  /// Checks if `prefix` is a strict prefix of `buffer`. Uses `equal` to
  /// compare elements.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  /// buffer.add(4);
  ///
  /// let pre = Buffer.Buffer<Nat>(3);
  /// pre.add(1);
  /// pre.add(2);
  /// pre.add(3);
  /// Buffer.isStrictPrefixOf(pre, buffer, Nat.equal); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size of prefix)` | `O(size of prefix)` |
  public func isStrictPrefixOf<X>(prefix : Buffer<X>, buffer : Buffer<X>, equal : (X, X) -> Bool) : Bool {
    if (buffer.size() <= prefix.size()) {
      return false
    };
    isPrefixOf(prefix, buffer, equal)
  };

  /// Returns the suffix of `buffer` of length `length`.
  /// Traps if `length`is greater than the size of `buffer`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  /// buffer.add(4);
  ///
  /// let suf = Buffer.suffix(buffer, 3); // => [2, 3, 4]
  /// Buffer.toText(suf, Nat.toText);
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(length)` | `O(length)` |
  public func suffix<X>(buffer : Buffer<X>, length : Nat) : Buffer<X> {
    let size = buffer.size();

    if (length > size) {
      Prim.trap "Buffer index out of bounds in suffix"
    };

    let newBuffer = Buffer<X>(newCapacity length);

    var i = size - length : Nat;
    while (i < size) {
      newBuffer.add(buffer.get(i));

      i += 1
    };

    newBuffer
  };

  /// Checks if `suffix` is a suffix of `buffer`. Uses `equal` to compare
  /// elements.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  /// buffer.add(4);
  ///
  /// let suf = Buffer.Buffer<Nat>(3);
  /// suf.add(2);
  /// suf.add(3);
  /// suf.add(4);
  /// Buffer.isSuffixOf(suf, buffer, Nat.equal); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(length of suffix)` | `O(length of suffix)` |
  public func isSuffixOf<X>(suffix : Buffer<X>, buffer : Buffer<X>, equal : (X, X) -> Bool) : Bool {
    let suffixSize = suffix.size();
    let bufferSize = buffer.size();
    if (bufferSize < suffixSize) {
      return false
    };

    var i = bufferSize;
    var j = suffixSize;
    while (i >= 1 and j >= 1) {
      i -= 1;
      j -= 1;
      if (not equal(buffer.get(i), suffix.get(j))) {
        return false
      }
    };

    return true
  };

  /// Checks if `suffix` is a strict suffix of `buffer`. Uses `equal` to compare
  /// elements.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  /// buffer.add(4);
  ///
  /// let suf = Buffer.Buffer<Nat>(3);
  /// suf.add(2);
  /// suf.add(3);
  /// suf.add(4);
  /// Buffer.isStrictSuffixOf(suf, buffer, Nat.equal); // => true
  /// ```
  ///
/// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(length)` | `O(length)` |
  public func isStrictSuffixOf<X>(suffix : Buffer<X>, buffer : Buffer<X>, equal : (X, X) -> Bool) : Bool {
    if (buffer.size() <= suffix.size()) {
      return false
    };
    isSuffixOf(suffix, buffer, equal)
  };

  /// Returns true if every element in `buffer` satisfies `predicate`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// buffer.add(2);
  /// buffer.add(3);
  /// buffer.add(4);
  ///
  /// Buffer.forAll<Nat>(buffer, func x { x > 1 }); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func forAll<X>(buffer : Buffer<X>, predicate : X -> Bool) : Bool {
    for (element in buffer.vals()) {
      if (not predicate element) {
        return false
      }
    };

    true
  };

  /// Returns true if some element in `buffer` satisfies `predicate`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// buffer.add(2);
  /// buffer.add(3);
  /// buffer.add(4);
  ///
  /// Buffer.forSome<Nat>(buffer, func x { x > 3 }); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func forSome<X>(buffer : Buffer<X>, predicate : X -> Bool) : Bool {
    for (element in buffer.vals()) {
      if (predicate element) {
        return true
      }
    };

    false
  };

  /// Returns true if no element in `buffer` satisfies `predicate`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// buffer.add(2);
  /// buffer.add(3);
  /// buffer.add(4);
  ///
  /// Buffer.forNone<Nat>(buffer, func x { x == 0 }); // => true
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func forNone<X>(buffer : Buffer<X>, predicate : X -> Bool) : Bool {
    for (element in buffer.vals()) {
      if (predicate element) {
        return false
      }
    };

    true
  };

  /// Creates an `array` containing elements from `buffer`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  ///
  /// Buffer.toArray<Nat>(buffer); // => [1, 2, 3]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func toArray<X>(buffer : Buffer<X>) : [X] =
  // immutable clone of array
  Prim.Array_tabulate<X>(
    buffer.size(),
    func(i : Nat) : X { buffer.get(i) }
  );

  /// Creates a mutable array containing elements from `buffer`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  ///
  /// Buffer.toVarArray<Nat>(buffer); // => [1, 2, 3]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func toVarArray<X>(buffer : Buffer<X>) : [var X] {
    let size = buffer.size();
    if (size == 0) { [var] } else {
      let newArray = Prim.Array_init<X>(size, buffer.get(0));
      var i = 1;
      while (i < size) {
        newArray[i] := buffer.get(i);
        i += 1
      };
      newArray
    }
  };

  /// Creates a `buffer` containing elements from `array`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let array = [2, 3];
  ///
  /// let buf = Buffer.fromArray<Nat>(array); // => [2, 3]
  /// Buffer.toText(buf, Nat.toText);
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func fromArray<X>(array : [X]) : Buffer<X> {
    // When returning new buffer, if possible, set the capacity
    // to the capacity of the old buffer. Otherwise, return them
    // at 2/3 capacity (like in this case). Alternative is to
    // calculate what the size would be if the elements were
    // sequentially added using `add`. This current strategy (2/3)
    // is the upper bound of that calculation (if the last element
    // added caused a capacity increase).
    let newBuffer = Buffer<X>(newCapacity(array.size()));

    for (element in array.vals()) {
      newBuffer.add(element)
    };

    newBuffer
  };

  /// Creates a `buffer` containing elements from `array`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let array = [var 1, 2, 3];
  ///
  /// let buf = Buffer.fromVarArray<Nat>(array); // => [1, 2, 3]
  /// Buffer.toText(buf, Nat.toText);
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func fromVarArray<X>(array : [var X]) : Buffer<X> {
    let newBuffer = Buffer<X>(newCapacity(array.size()));

    for (element in array.vals()) {
      newBuffer.add(element)
    };

    newBuffer
  };

  /// Creates a `buffer` containing elements from `iter`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let array = [1, 1, 1];
  /// let iter = array.vals();
  ///
  /// let buf = Buffer.fromIter<Nat>(iter); // => [1, 1, 1]
  /// Buffer.toText(buf, Nat.toText);
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func fromIter<X>(iter : { next : () -> ?X }) : Buffer<X> {
    let newBuffer = Buffer<X>(DEFAULT_CAPACITY); // can't get size from `iter`

    for (element in iter) {
      newBuffer.add(element)
    };

    newBuffer
  };

  /// Reallocates the array underlying `buffer` such that capacity == size.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// let buffer = Buffer.Buffer<Nat>(10);
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  ///
  /// Buffer.trimToSize<Nat>(buffer);
  /// buffer.capacity(); // => 3
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func trimToSize<X>(buffer : Buffer<X>) {
    let size = buffer.size();
    if (size < buffer.capacity()) {
      buffer.reserve(size)
    }
  };

  /// Creates a new `buffer` by applying `f` to each element in `buffer`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  ///
  /// let newBuf = Buffer.map<Nat, Nat>(buffer, func (x) { x + 1 });
  /// Buffer.toText(newBuf, Nat.toText); // => [2, 3, 4]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func map<X, Y>(buffer : Buffer<X>, f : X -> Y) : Buffer<Y> {
    let newBuffer = Buffer<Y>(buffer.capacity());

    for (element in buffer.vals()) {
      newBuffer.add(f element)
    };

    newBuffer
  };

  /// Applies `f` to each element in `buffer`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  /// import Debug "mo:base/Debug";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  ///
  /// Buffer.iterate<Nat>(buffer, func (x) {
  ///   Debug.print(Nat.toText(x)); // prints each element in buffer
  /// });
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  ///
  public func iterate<X>(buffer : Buffer<X>, f : X -> ()) {
    for (element in buffer.vals()) {
      f element
    }
  };

  /// Applies `f` to each element in `buffer` and its index.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  ///
  /// let newBuf = Buffer.mapEntries<Nat, Nat>(buffer, func (x, i) { x + i + 1 });
  /// Buffer.toText(newBuf, Nat.toText); // => [2, 4, 6]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func mapEntries<X, Y>(buffer : Buffer<X>, f : (Nat, X) -> Y) : Buffer<Y> {
    let newBuffer = Buffer<Y>(buffer.capacity());

    var i = 0;
    let size = buffer.size();
    while (i < size) {
      newBuffer.add(f(i, buffer.get(i)));
      i += 1
    };

    newBuffer
  };

  /// Creates a new buffer by applying `f` to each element in `buffer`,
  /// and keeping all non-null elements.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  ///
  /// let newBuf = Buffer.mapFilter<Nat, Nat>(buffer, func (x) {
  ///  if (x > 1) {
  ///    ?(x * 2);
  ///  } else {
  ///    null;
  ///  }
  /// });
  /// Buffer.toText(newBuf, Nat.toText); // => [4, 6]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func mapFilter<X, Y>(buffer : Buffer<X>, f : X -> ?Y) : Buffer<Y> {
    let newBuffer = Buffer<Y>(buffer.capacity());

    for (element in buffer.vals()) {
      switch (f element) {
        case (?element) {
          newBuffer.add(element)
        };
        case _ {}
      }
    };

    newBuffer
  };

  /// Creates a new buffer by applying `f` to each element in `buffer`.
  /// If any invocation of `f` produces an `#err`, returns an `#err`. Otherwise
  /// Returns an `#ok` containing the new buffer.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Result "mo:base/Result";
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  ///
  /// let result = Buffer.mapResult<Nat, Nat, Text>(buffer, func (k) {
  ///  if (k > 0) {
  ///    #ok(k);
  ///  } else {
  ///    #err("One or more elements are zero.");
  ///  }
  /// });
  ///
  /// Result.mapOk<Buffer.Buffer<Nat>, [Nat], Text>(result, func buffer = Buffer.toArray(buffer)) // => #ok([1, 2, 3])
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func mapResult<X, Y, E>(buffer : Buffer<X>, f : X -> Result.Result<Y, E>) : Result.Result<Buffer<Y>, E> {
    let newBuffer = Buffer<Y>(buffer.capacity());

    for (element in buffer.vals()) {
      switch (f element) {
        case (#ok result) {
          newBuffer.add(result)
        };
        case (#err e) {
          return #err e
        }
      }
    };

    #ok newBuffer
  };

  /// Creates a new `buffer` by applying `k` to each element in `buffer`,
  /// and concatenating the resulting buffers in order. This operation
  /// is similar to what in other functional languages is known as monadic bind.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  ///
  /// let chain = Buffer.chain<Nat, Nat>(buffer, func (x) {
  /// let b = Buffer.Buffer<Nat>(2);
  /// b.add(x);
  /// b.add(x * 2);
  /// return b;
  /// });
  /// Buffer.toText(chain, Nat.toText); // => [1, 2, 2, 4, 3, 6]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func chain<X, Y>(buffer : Buffer<X>, k : X -> Buffer<Y>) : Buffer<Y> {
    let newBuffer = Buffer<Y>(buffer.size() * 4);

    for (element in buffer.vals()) {
      newBuffer.append(k element)
    };

    newBuffer
  };

  /// Collapses the elements in `buffer` into a single value by starting with `base`
  /// and progessively combining elements into `base` with `combine`. Iteration runs
  /// left to right.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  ///
  /// Buffer.foldLeft<Text, Nat>(buffer, "", func (acc, x) { acc # Nat.toText(x)}); // => "123"
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func foldLeft<A, X>(buffer : Buffer<X>, base : A, combine : (A, X) -> A) : A {
    var accumulation = base;

    for (element in buffer.vals()) {
      accumulation := combine(accumulation, element)
    };

    accumulation
  };

  /// Collapses the elements in `buffer` into a single value by starting with `base`
  /// and progessively combining elements into `base` with `combine`. Iteration runs
  /// right to left.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  ///
  /// Buffer.foldRight<Nat, Text>(buffer, "", func (x, acc) { Nat.toText(x) # acc }); // => "123"
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func foldRight<X, A>(buffer : Buffer<X>, base : A, combine : (X, A) -> A) : A {
    let size = buffer.size();
    if (size == 0) {
      return base
    };
    var accumulation = base;

    var i = size;
    while (i >= 1) {
      i -= 1; // to avoid Nat underflow, subtract first and stop iteration at 1
      accumulation := combine(buffer.get(i), accumulation)
    };

    accumulation
  };

  /// Returns the first element of `buffer`. Traps if `buffer` is empty.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  ///
  /// Buffer.first(buffer); // => 1
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(1)` | `O(1)` |
  public func first<X>(buffer : Buffer<X>) : X = buffer.get(0);

  /// Returns the last element of `buffer`. Traps if `buffer` is empty.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  ///
  /// Buffer.last(buffer); // => 3
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(1)` | `O(1)` |
  public func last<X>(buffer : Buffer<X>) : X = buffer.get(buffer.size() - 1);

  /// Returns a new `buffer` with capacity and size 1, containing `element`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let buffer = Buffer.make<Nat>(1);
  /// Buffer.toText(buffer, Nat.toText); // => [1]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(1)` | `O(1)` |
  public func make<X>(element : X) : Buffer<X> {
    let newBuffer = Buffer<X>(1);
    newBuffer.add(element);
    newBuffer
  };

  /// Reverses the order of elements in `buffer`.
  ///
  /// Example:
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  ///
  /// Buffer.reverse(buffer);
  /// Buffer.toText(buffer, Nat.toText); // => [3, 2, 1]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(1)` |
  public func reverse<X>(buffer : Buffer<X>) {
    let size = buffer.size();
    if (size == 0) {
      return
    };

    var i = 0;
    var j = size - 1 : Nat;
    var temp = buffer.get(0);
    while (i < size / 2) {
      temp := buffer.get(j);
      buffer.put(j, buffer.get(i));
      buffer.put(i, temp);
      i += 1;
      j -= 1
    }
  };

  /// Merges two sorted buffers into a single sorted `buffer`, using `compare` to define
  /// the ordering. The final ordering is stable. Behavior is undefined if either
  /// `buffer1` or `buffer2` is not sorted.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let buffer1 = Buffer.Buffer<Nat>(2);
  /// buffer1.add(1);
  /// buffer1.add(2);
  /// buffer1.add(4);
  ///
  /// let buffer2 = Buffer.Buffer<Nat>(2);
  /// buffer2.add(2);
  /// buffer2.add(4);
  /// buffer2.add(6);
  ///
  /// let merged = Buffer.merge<Nat>(buffer1, buffer2, Nat.compare);
  /// Buffer.toText(merged, Nat.toText); // => [1, 2, 2, 4, 4, 6]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size1 + size2)` | `O(size1 + size2)` |
  public func merge<X>(buffer1 : Buffer<X>, buffer2 : Buffer<X>, compare : (X, X) -> Order) : Buffer<X> {
    let size1 = buffer1.size();
    let size2 = buffer2.size();

    let newBuffer = Buffer<X>(newCapacity(size1 + size2));

    var pointer1 = 0;
    var pointer2 = 0;

    while (pointer1 < size1 and pointer2 < size2) {
      let current1 = buffer1.get(pointer1);
      let current2 = buffer2.get(pointer2);

      switch (compare(current1, current2)) {
        case (#less) {
          newBuffer.add(current1);
          pointer1 += 1
        };
        case _ {
          newBuffer.add(current2);
          pointer2 += 1
        }
      }
    };

    while (pointer1 < size1) {
      newBuffer.add(buffer1.get(pointer1));
      pointer1 += 1
    };

    while (pointer2 < size2) {
      newBuffer.add(buffer2.get(pointer2));
      pointer2 += 1
    };

    newBuffer
  };

  /// Eliminates all duplicate elements in `buffer` as defined by `compare`.
  /// Elimination is stable with respect to the original ordering of the elements.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  ///
  /// Buffer.removeDuplicates<Nat>(buffer, Nat.compare);
  /// Buffer.toText(buffer, Nat.toText); // => [1, 2, 3]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size * log(size))` | `O(size)` |
  public func removeDuplicates<X>(buffer : Buffer<X>, compare : (X, X) -> Order) {
    let size = buffer.size();
    let indices = Prim.Array_tabulate<(Nat, X)>(size, func i = (i, buffer.get(i)));
    // Sort based on element, while carrying original index information
    // This groups together the duplicate elements
    let sorted = Array.sort<(Nat, X)>(indices, func(pair1, pair2) = compare(pair1.1, pair2.1));
    let uniques = Buffer<(Nat, X)>(size);

    // Iterate over elements
    var i = 0;
    while (i < size) {
      var j = i;
      // Iterate over duplicate elements, and find the smallest index among them (for stability)
      var minIndex = sorted[j];
      label duplicates while (j < (size - 1 : Nat)) {
        let pair1 = sorted[j];
        let pair2 = sorted[j + 1];
        switch (compare(pair1.1, pair2.1)) {
          case (#equal) {
            if (pair2.0 < pair1.0) {
              minIndex := pair2
            };
            j += 1
          };
          case _ {
            break duplicates
          }
        }
      };

      uniques.add(minIndex);
      i := j + 1
    };

    // resort based on original ordering and place back in buffer
    uniques.sort(
      func(pair1, pair2) {
        if (pair1.0 < pair2.0) {
          #less
        } else if (pair1.0 == pair2.0) {
          #equal
        } else {
          #greater
        }
      }
    );

    buffer.clear();
    buffer.reserve(uniques.size());
    for (element in uniques.vals()) {
      buffer.add(element.1)
    }
  };

  /// Splits `buffer` into a pair of buffers where all elements in the left
  /// `buffer` satisfy `predicate` and all elements in the right `buffer` do not.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  /// buffer.add(4);
  /// buffer.add(5);
  /// buffer.add(6);
  ///
  /// let partitions = Buffer.partition<Nat>(buffer, func (x) { x % 2 == 0 });
  /// (Buffer.toArray(partitions.0), Buffer.toArray(partitions.1)) // => ([2, 4, 6], [1, 3, 5])
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func partition<X>(buffer : Buffer<X>, predicate : X -> Bool) : (Buffer<X>, Buffer<X>) {
    let size = buffer.size();
    let trueBuffer = Buffer<X>(size);
    let falseBuffer = Buffer<X>(size);

    for (element in buffer.vals()) {
      if (predicate element) {
        trueBuffer.add(element)
      } else {
        falseBuffer.add(element)
      }
    };

    (trueBuffer, falseBuffer)
  };

  /// Splits the buffer into two buffers at `index`, where the left buffer contains
  /// all elements with indices less than `index`, and the right buffer contains all
  /// elements with indices greater than or equal to `index`. Traps if `index` is out
  /// of bounds.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  /// buffer.add(4);
  /// buffer.add(5);
  /// buffer.add(6);
  ///
  /// let split = Buffer.split<Nat>(buffer, 3);
  /// (Buffer.toArray(split.0), Buffer.toArray(split.1)) // => ([1, 2, 3], [4, 5, 6])
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |

  public func split<X>(buffer : Buffer<X>, index : Nat) : (Buffer<X>, Buffer<X>) {
    let size = buffer.size();

    if (index < 0 or index > size) {
      Prim.trap "Index out of bounds in split"
    };

    let buffer1 = Buffer<X>(newCapacity index);
    let buffer2 = Buffer<X>(newCapacity(size - index));

    var i = 0;
    while (i < index) {
      buffer1.add(buffer.get(i));
      i += 1
    };
    while (i < size) {
      buffer2.add(buffer.get(i));
      i += 1
    };

    (buffer1, buffer2)
  };

  /// Breaks up `buffer` into buffers of size `size`. The last chunk may
  /// have less than `size` elements if the number of elements is not divisible
  /// by the chunk size.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  /// buffer.add(4);
  /// buffer.add(5);
  /// buffer.add(6);
  ///
  /// let chunks = Buffer.chunk<Nat>(buffer, 3);
  /// Buffer.toText<Buffer.Buffer<Nat>>(chunks, func buf = Buffer.toText(buf, Nat.toText)); // => [[1, 2, 3], [4, 5, 6]]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(number of elements in buffer)` | `O(number of elements in buffer)` |
  ///
  public func chunk<X>(buffer : Buffer<X>, size : Nat) : Buffer<Buffer<X>> {
    if (size == 0) {
      Prim.trap "Chunk size must be non-zero in chunk"
    };

    // ceil(buffer.size() / size)
    let newBuffer = Buffer<Buffer<X>>((buffer.size() + size - 1) / size);

    var newInnerBuffer = Buffer<X>(newCapacity size);
    var innerSize = 0;
    for (element in buffer.vals()) {
      if (innerSize == size) {
        newBuffer.add(newInnerBuffer);
        newInnerBuffer := Buffer<X>(newCapacity size);
        innerSize := 0
      };
      newInnerBuffer.add(element);
      innerSize += 1
    };
    if (innerSize > 0) {
      newBuffer.add(newInnerBuffer)
    };

    newBuffer
  };

  /// Groups equal and adjacent elements in the list into sub lists.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(2);
  /// buffer.add(4);
  /// buffer.add(5);
  /// buffer.add(5);
  ///
  /// let grouped = Buffer.groupBy<Nat>(buffer, func (x, y) { x == y });
  /// Buffer.toText<Buffer.Buffer<Nat>>(grouped, func buf = Buffer.toText(buf, Nat.toText)); // => [[1], [2, 2], [4], [5, 5]]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func groupBy<X>(buffer : Buffer<X>, equal : (X, X) -> Bool) : Buffer<Buffer<X>> {
    let size = buffer.size();
    let newBuffer = Buffer<Buffer<X>>(size);
    if (size == 0) {
      return newBuffer
    };

    var i = 0;
    var baseElement = buffer.get(0);
    var newInnerBuffer = Buffer<X>(size);
    while (i < size) {
      let element = buffer.get(i);

      if (equal(baseElement, element)) {
        newInnerBuffer.add(element)
      } else {
        newBuffer.add(newInnerBuffer);
        baseElement := element;
        newInnerBuffer := Buffer<X>(size - i);
        newInnerBuffer.add(element)
      };
      i += 1
    };
    if (newInnerBuffer.size() > 0) {
      newBuffer.add(newInnerBuffer)
    };

    newBuffer
  };

  /// Flattens the `buffer` of buffers into a single `buffer`.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// let buffer = Buffer.Buffer<Buffer.Buffer<Nat>>(1);
  ///
  /// let inner1 = Buffer.Buffer<Nat>(2);
  /// inner1.add(1);
  /// inner1.add(2);
  ///
  /// let inner2 = Buffer.Buffer<Nat>(2);
  /// inner2.add(3);
  /// inner2.add(4);
  ///
  /// buffer.add(inner1);
  /// buffer.add(inner2);
  /// // buffer = [[1, 2], [3, 4]]
  ///
  /// let flat = Buffer.flatten<Nat>(buffer);
  /// Buffer.toText<Nat>(flat, Nat.toText); // => [1, 2, 3, 4]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(number of elements in buffer)` | `O(number of elements in buffer)` |
  public func flatten<X>(buffer : Buffer<Buffer<X>>) : Buffer<X> {
    let size = buffer.size();
    if (size == 0) {
      return Buffer<X>(0)
    };

    let newBuffer = Buffer<X>(
      if (buffer.get(0).size() != 0) {
        newCapacity(buffer.get(0).size() * size)
      } else {
        newCapacity(size)
      }
    );

    for (innerBuffer in buffer.vals()) {
      for (innerElement in innerBuffer.vals()) {
        newBuffer.add(innerElement)
      }
    };

    newBuffer
  };

  /// Combines the two buffers into a single buffer of pairs, pairing together
  /// elements with the same index. If one buffer is longer than the other, the
  /// remaining elements from the longer buffer are not included.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  ///
  /// let buffer1 = Buffer.Buffer<Nat>(2);
  /// buffer1.add(1);
  /// buffer1.add(2);
  /// buffer1.add(3);
  ///
  /// let buffer2 = Buffer.Buffer<Nat>(2);
  /// buffer2.add(4);
  /// buffer2.add(5);
  ///
  /// let zipped = Buffer.zip(buffer1, buffer2);
  /// Buffer.toArray(zipped); // => [(1, 4), (2, 5)]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(min(size1, size2))` | `O(min(size1, size2))` |
  public func zip<X, Y>(buffer1 : Buffer<X>, buffer2 : Buffer<Y>) : Buffer<(X, Y)> {
    // compiler should pull lamda out as a static function since it is fully closed
    zipWith<X, Y, (X, Y)>(buffer1, buffer2, func(x, y) = (x, y))
  };

  /// Combines the two buffers into a single buffer, pairing together
  /// elements with the same index and combining them using `zip`. If
  /// one buffer is longer than the other, the remaining elements from
  /// the longer buffer are not included.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  ///
  /// let buffer1 = Buffer.Buffer<Nat>(2);
  /// buffer1.add(1);
  /// buffer1.add(2);
  /// buffer1.add(3);
  ///
  /// let buffer2 = Buffer.Buffer<Nat>(2);
  /// buffer2.add(4);
  /// buffer2.add(5);
  /// buffer2.add(6);
  ///
  /// let zipped = Buffer.zipWith<Nat, Nat, Nat>(buffer1, buffer2, func (x, y) { x + y });
  /// Buffer.toArray(zipped) // => [5, 7, 9]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(min(size1, size2))` | `O(min(size1, size2))` |
  ///
  public func zipWith<X, Y, Z>(buffer1 : Buffer<X>, buffer2 : Buffer<Y>, zip : (X, Y) -> Z) : Buffer<Z> {
    let size1 = buffer1.size();
    let size2 = buffer2.size();
    let minSize = if (size1 < size2) { size1 } else { size2 };

    var i = 0;
    let newBuffer = Buffer<Z>(newCapacity minSize);
    while (i < minSize) {
      newBuffer.add(zip(buffer1.get(i), buffer2.get(i)));
      i += 1
    };
    newBuffer
  };

  /// Creates a new buffer taking elements in order from `buffer` until predicate
  /// returns false.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  ///
  /// let newBuf = Buffer.takeWhile<Nat>(buffer, func (x) { x < 3 });
  /// Buffer.toText(newBuf, Nat.toText); // => [1, 2]
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func takeWhile<X>(buffer : Buffer<X>, predicate : X -> Bool) : Buffer<X> {
    let newBuffer = Buffer<X>(buffer.size());

    for (element in buffer.vals()) {
      if (not predicate element) {
        return newBuffer
      };
      newBuffer.add(element)
    };

    newBuffer
  };

  /// Creates a new buffer excluding elements in order from `buffer` until predicate
  /// returns false.
  ///
  /// Example:
  ///
  /// ```motoko include=initialize
  /// import Nat "mo:base/Nat";
  ///
  /// buffer.add(1);
  /// buffer.add(2);
  /// buffer.add(3);
  ///
  /// let newBuf = Buffer.dropWhile<Nat>(buffer, func x { x < 3 }); // => [3]
  /// Buffer.toText(newBuf, Nat.toText);
  /// ```
  ///
  /// | Runtime   | Space     |
  /// |-----------|-----------|
  /// | `O(size)` | `O(size)` |
  public func dropWhile<X>(buffer : Buffer<X>, predicate : X -> Bool) : Buffer<X> {
    let size = buffer.size();
    let newBuffer = Buffer<X>(size);

    var i = 0;
    var take = false;
    label iter for (element in buffer.vals()) {
      if (not (take or predicate element)) {
        take := true
      };
      if (take) {
        newBuffer.add(element)
      }
    };
    newBuffer
  }
}
