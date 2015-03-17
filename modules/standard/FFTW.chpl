/*
 * Copyright 2004-2015 Cray Inc.
 * Other additional copyright holders may be indicated within.
 * 
 * The entirety of this work is licensed under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * 
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Wrapper for FFTW version 3.

/*
  FFT computations via key routines from FFTW (version 3)

  This module defines Chapel wrappers for key 64-bit routines from
  FFTW (http://www.fftw.org), version 3.  Over time, the intention is
  to expand this module to support additional routines, prioritizing
  based on requests and feedback from users.  Also, see the
  :mod:`FFTW_MT` module which provides support for calls to the
  multi-threaded FFTW implementation.


  To use this module:

  1. Ensure that FFTW (version 3) is installed on your system and that
     the header and library files (e.g., fftw3.h, libfftw3.*) are
     either installed in a standard system location or that your C
     compiler's environment variables are set up to find them.

  2. Add ``use FFTW;`` to your Chapel code.

  3. Compile and run your Chapel program as usual.


  As in standard FFTW usage, the flow is to:

  1. Create plan(s) using the :proc:`plan_dft* <plan_dft>` routines.

  2. Execute the plan(s) one or more times using :proc:`execute`.

  3. Destroy the plan(s) using :proc:`destroy_plan`.

  4. Call :proc:`cleanup`.


  Note that each of the Chapel :proc:`plan_dft* <plan_dft>` routines
  support both `in-place` and `out-of-place` versions of the
  transforms, where the former versions use a single array for both
  input and output, and the latter use two distinct arrays.
  
  In future versions of this interface, we anticipate replacing
  C-oriented arguments in the `plan_dft*()` routines (like `flags`)
  with more precise arguments that take advantage of Chapel's support
  for default argument values and keyword-based argument passing.
*/

//
// - How do we feel about FFTW_ALLCAPS names given that the routines
//   themselves don't have fftw_ prefixes, that they're defined as
//   c_int's, and that they're all-caps?
//
// - Related question about fftw_ types taking type c_int, though
//   maybe we don't care that much (as compared to other interfaces)
//   since symbolic values are taken in? (i.e., we won't run into
//   32- vs. 64-bit issues...)
//

module FFTW {

  use SysCTypes;
  use "fftw3.h", "-lfftw3";


  /*
    Disable execution-time array size checks in the FFTW
    :proc:`plan_dft` routine.
   */
  config param noFFTWsizeChecks = false;

  /*
    An opaque type used to store and reuse FFTW plans across multiple
    routines.
  */
  extern type fftw_plan; // opaque type


  // Planner functions
  // Complex : 4.3.1
  // NOTE : We pass in arrays using ref 

  // TODO: Can we have the plan_dft() routine below take in native
  // Chapel types without changing the external C constants from
  // type c_int?  Probably given that Chapel's int will be >=
  // C's int for the forseeable future.  See also the TODO above
  // about whether we'd want to represent those constants using
  // more native Chapel types anyway.

  /*
    Creates a plan for an out-of-place complex-to-complex DFT.

    :arg input: The input array, which can be of any rank
    :type input: [] `complex(128)`

    :arg output: The output array, whose size and shape must match the input array's
    :type output: [] `complex(128)`
    
    :arg sign: :const:`FFTW_FORWARD` or :const:`FFTW_BACKWARD`
    :type sign: c_int

    :arg flags: the bitwise-or of any planning-rigor or algorithm-restriction flags that should be used in creating the plan (e.g., :const:`FFTW_MEASURE` ``|`` :const:`FFTW_PRESERVE_INPUT`)
    :type flags: c_int

    :returns: The :type:`fftw_plan` representing the resulting plan
  */
  proc plan_dft(input: [] complex(128), output: [] complex(128), 
                 sign: c_int, flags: c_uint) : fftw_plan
  {
    if !noFFTWsizeChecks then
      for i in 1..input.rank do
        if (input.domain.dim(i).size != output.domain.dim(i).size) then
          halt("In plan_dft(), input and output arrays don't have same size in dimension ", i);

    return plan_dft_help(input, output, sign, flags);
  }


  /*
    Creates a plan for an in-place complex-to-complex DFT.

    :arg arr: The array to use as the in-place input/output array.
    :type arr: [] `complex(128)`

    :arg sign: :const:`FFTW_FORWARD` or :const:`FFTW_BACKWARD`
    :type sign: c_int

    :arg flags: the bitwise-or of any planning-rigor or algorithm-restriction flags that should be used in creating the plan (e.g., :const:`FFTW_MEASURE` ``|`` :const:`FFTW_PRESERVE_INPUT`)
    :type flags: c_int

    :returns: The :type:`fftw_plan` representing the resulting plan
  */
  proc plan_dft(arr: [] complex(128), sign: c_int, flags: c_uint): fftw_plan {
    return plan_dft_help(arr, arr, sign, flags);
  }

  //
  // Though not strictly necessary, this helper routine is to avoid
  // doing the size check for the in-place case.  This is the kind
  // of thing we'd like to mark as "private" once we have that
  // capability.  I could move it into a sub-module for the time
  // being, but want to keep the diff with the previous version of
  // the code minimal.  -BLC
  // 
  pragma "no doc"
  proc plan_dft_help(input: [] complex(128), output: [] complex(128), 
                 sign: c_int, flags: c_uint) : fftw_plan
  {
    param rank = input.rank;

    var dims: rank*c_int;
    for param i in 1..rank do
      dims(i) = input.domain.dim(i).size.safeCast(c_int);

    return C_FFTW.fftw_plan_dft(rank.safeCast(c_int), dims, input, 
                                     output, sign, flags);
  }


  // Real-to-complex and complex-to-real planning routines There are
  // two cases that we treat independently here : in-place and
  // out-of-place transforms

  /*
    Create a plan for a real-to-complex, out-of-place DFT.

    :arg input: The input array, which can be of any rank
    :type input: [] `real(64)`

    :arg output: The output array, whose rank must match the input array's.  The leading dimension of this array should be n/2 + 1, where n is the size of the real array's corresponding dimension.  See the `FFTW documentation <http://www.fftw.org/fftw2_doc/fftw_2.html#SEC6>`_ for more information.
    :type output: [] `complex(128)`
    
    :arg flags: the bitwise-or of any planning-rigor or algorithm-restriction flags that should be used in creating the plan (e.g., :const:`FFTW_MEASURE` ``|`` :const:`FFTW_PRESERVE_INPUT`)
    :type flags: c_int

    :returns: The :type:`fftw_plan` representing the resulting plan
  */
  proc plan_dft_r2c(input : [] real(64), output : [] complex(128), flags :c_uint) : fftw_plan
  {
    param rank = input.rank: c_int;

    var dims: rank*c_int;
    for param i in 1..rank do
      dims(i) = input.domain.dim(i).size: c_int;

    return C_FFTW.fftw_plan_dft_r2c(rank, dims, input, output, flags);
  }

  // In-place routines, note that these take in the true leading dimension
  // TODO : We should put in checks to see that the sizes are consistent
  // TODO : We should check on types...
  /*
    Create a plan for a real-to-complex, in-place DFT.

    :arg realDom: Describes the indices of the 'real' view of the array
    :type realDom: `domain`

    :arg arr: The array to be used as the in-place input/output array.  If passing in an array of `real` elements, the leading dimension of the array must be padded to store 2(n/2)+1 elements, where `n` is the size of the corresponding dimension of `realDom`.  If passing in an array of `complex` elements, the leading dimension should be (n/2 + 1).  See the `FFTW documentation <http://www.fftw.org/fftw2_doc/fftw_2.html#SEC6>`_ for more information.
    :type arr: [] `T` where `T` is of type `real` or `complex`

    :arg flags: the bitwise-or of any planning-rigor or algorithm-restriction flags that should be used in creating the plan (e.g., :const:`FFTW_MEASURE` ``|`` :const:`FFTW_PRESERVE_INPUT`)
    :type flags: c_int

    :returns: The :type:`fftw_plan` representing the resulting plan
   */
  proc plan_dft_r2c(realDom : domain, arr : [] ?t, flags : c_uint) : fftw_plan 
  {
    param rank = realDom.rank: c_int;

    var dims: rank*c_int;
    for param i in 1..rank do
      dims(i) = realDom.dim(i).size: c_int;

    return C_FFTW.fftw_plan_dft_r2c(rank, dims, arr, arr, flags);
  }

  /*
    Create a plan for a complex-to-real, out-of-place DFT.

    :arg input: The input array, which can be of any rank
    :type input: [] `complex(128)`

    :arg output: The output array, whose rank must match the input array's.  The leading dimension of this array should be n/2 + 1, where n is the size of the real array's corresponding dimension.  See the `FFTW documentation <http://www.fftw.org/fftw2_doc/fftw_2.html#SEC6>`_ for more information.
    :type output: [] `real(64)`
    
    :arg flags: the bitwise-or of any planning-rigor or algorithm-restriction flags that should be used in creating the plan (e.g., :const:`FFTW_MEASURE` ``|`` :const:`FFTW_PRESERVE_INPUT`)
    :type flags: c_int

    :returns: The :type:`fftw_plan` representing the resulting plan
  */
  proc plan_dft_c2r(input : [] complex(128), output : [] real(64), flags :c_uint) : fftw_plan
  {
    param rank = output.rank: c_int; // The dimensions are that of the real array

    var dims: rank*c_int;
    for param i in 1..rank do
      dims(i) = output.domain.dim(i).size: c_int;

    return C_FFTW.fftw_plan_dft_c2r(rank, dims, input, output, flags);
  }

  /*
    Create a plan for a complex-to-real, in-place DFT.

    :arg realDom: Describes the indices of the 'real' view of the array
    :type realDom: `domain`

    :arg arr: The array to be used as the in-place input/output array.  If passing in an array of `real` elements, the leading dimension of the array must be padded to store 2(n/2)+1 elements, where `n` is the size of the corresponding dimension of `realDom`.  If passing in an array of `complex` elements, the leading dimension should be (n/2 + 1).  See the `FFTW documentation <http://www.fftw.org/fftw2_doc/fftw_2.html#SEC6>`_ for more information.
    :type arr: [] `T` where `T` is of type `real` or `complex`

    :arg flags: the bitwise-or of any planning-rigor or algorithm-restriction flags that should be used in creating the plan (e.g., :const:`FFTW_MEASURE` ``|`` :const:`FFTW_PRESERVE_INPUT`)
    :type flags: c_int

    :returns: The :type:`fftw_plan` representing the resulting plan
   */
  proc plan_dft_c2r(realDom : domain, arr: [] ?t, flags : c_uint) : fftw_plan 
  {
    param rank = realDom.rank: c_int;

    var dims: rank*c_int;
    for param i in 1..rank do
      dims(i) = realDom.dim(i).size: c_int;

    return C_FFTW.fftw_plan_dft_c2r(rank, dims, arr, arr, flags);
  }


  // Using plans 

  /*
    Execute an FFTW plan.

    :arg plan: The plan to execute, as computed by a `plan_dft*()` routine.
    :type plan: fftw_plan
  */
  proc execute(const plan: fftw_plan) {
   C_FFTW.fftw_execute(plan);
  }

  /*
    Destroy an FFTW plan.

    :arg plan: The plan to destroy
    :type plan: fftw_plan
  */
  proc destroy_plan(plan: fftw_plan) {
    C_FFTW.fftw_destroy_plan(plan);
  }


  /*
    Clean up FFTW overall.
  */
  proc cleanup() {
    C_FFTW.fftw_cleanup();
  }


  // Define the various planner flags
  // See Sec. 4.3.2 of FFTW manual "Planner Flags"

  //
  // TODO: Is it weird that we use FFTW_ names here, but not in
  // the routines?  Should we wrap the external flags so that
  // they can be ints or enums and avoid the all-caps C scheme
  // or is the familiarity better?
  //

  // Direction flags

  /* Request a forward transform (i.e., use a negative exponent in the tranform). */
  extern const FFTW_FORWARD : c_int;
  /* Request a backward transform (i.e., use a positive exponent in the transofmr). */
  extern const FFTW_BACKWARD : c_int;


  // Planning-rigor flags

  /* Specify that a simple heuristic should be used to pick a plan
     quickly.  This will prevent the input/output arrays from being
     overwritten during planning. */
  extern const FFTW_ESTIMATE : c_uint;

  /* Specify that FFTW should try and find an optimized plan by
     computing several FFTs and measuring their execution time.
     This can consume some time.
  */
  // TODO: If/when we support defaults, might say something like: This
  // is the default planning option.
  extern const FFTW_MEASURE : c_uint;

  /* Specify that FFTW should expend a greater effort finding an
     optimized plan. */
  extern const FFTW_PATIENT : c_uint;

  /* Specify that FFTW should expend an even greater effort finding an
     optimized plan. */
  extern const FFTW_EXHAUSTIVE : c_uint;

  /* This is a special planning mode that is useful for querying
     whether wisdom is available.  When using it, the plan is only
     created when wisdom is available for the given problem; otherwise
     a `null plan` is returned.  This can be combined with other flags
     to create a plan if the wisdom available was created in that mode
     (e.g., ``FFTW_WISDOM_ONLY | FFW_PATIENT``).  For more details on
     this flag and the previous four, refer to `Section 4.3.2
     <http://www.fftw.org/doc/Planner-Flags.html>`_ of the FFTW manual
  */
  extern const FFTW_WISDOM_ONLY : c_uint;


  // Algorithm-restriction flags

  /* Specify that an out-of-place transform is permitted to overwrite
     its input array with arbitrary data.  This permits more efficient
     algorithms to be used in some cases. */
  // TODO: When we're ready to mention defaults, add: "This is the default for
  // :proc:`plan_dft_c2r`. // NOTE: ...and hc2r once supported...
  extern const FFTW_DESTROY_INPUT : c_uint;

  /* Specify that an out-of-place transform cannot change its input
     array. */
  // TODO: When we're ready to mention defaults, add: This is the
  // default for :proc:`plan_dft` and :proc:`plan_dft_r2c`. */
  extern const FFTW_PRESERVE_INPUT : c_uint;

  /* Specify that the algorithm may not impose any unusual alignment
     requirements on the input/output arrays.  This flag should not be
     necessary for current Chapel use since the planner will
     automatically detect such cases.  For more details on this flag
     and the previous two, refer to `Section 4.3.2
     <http://www.fftw.org/doc/Planner-Flags.html>`_ of the FFTW manual.
  */  // NOTE: But it will be if/when the new-array execute interface is supported
  extern const FFTW_UNALIGNED : c_uint;



  pragma "no doc"
  module C_FFTW {
    extern proc fftw_plan_dft(rank: c_int, 
                              n,  // BLC: having trouble being specific
                                  // This is a const int* in C
                              in1: [] complex(128), 
                              out1: [] complex(128), 
                              sign : c_int, c_flags : c_uint) : fftw_plan;

    extern proc fftw_plan_dft_r2c(rank: c_int, 
                                  n,  // BLC: having trouble being specific
                                      // This is a const int* in C
                                  in1: [],
                                  out1: [], 
                                  c_flags : c_uint) : fftw_plan;

    extern proc fftw_plan_dft_c2r(rank: c_int, 
                                  n,  // BLC: having trouble being specific
                                      // This is a const int* in C
                                  in1: [],
                                  out1: [],
                                  c_flags : c_uint) : fftw_plan;

    extern proc fftw_execute(const plan : fftw_plan);
    
    extern proc fftw_destroy_plan(plan : fftw_plan);
    
    extern proc fftw_cleanup();
    
    extern proc fftw_init_threads() : c_int;
    
    extern proc fftw_cleanup_threads();
    
    extern proc fftw_plan_with_nthreads(n : c_int);
  }
}
