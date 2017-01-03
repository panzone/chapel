/*
 * Copyright 2004-2016 Cray Inc.
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

#ifndef _comm_ofi_internal_h_
#define _comm_ofi_internal_h_

/* Comm diagnostics stuff */
/* Dupe of the version in chpl-comm.h except with atomics */
struct commDiagnostics_atomic {
  atomic_uint_least64_t get;
  atomic_uint_least64_t get_nb;
  atomic_uint_least64_t put;
  atomic_uint_least64_t put_nb;
  atomic_uint_least64_t test_nb;
  atomic_uint_least64_t wait_nb;
  atomic_uint_least64_t try_nb;
  atomic_uint_least64_t execute_on;
  atomic_uint_least64_t execute_on_fast;
  atomic_uint_least64_t execute_on_nb;
};

struct commDiagnostics_atomic *chpl_getCommDiagnostics(void);
void chpl_commDiagnosticsInc(atomic_uint_least64_t *val);

#define CHPL_COMM_DIAGS_INC(comm_type)					\
    chpl_commDiagnosticsInc(&(chpl_getCommDiagnostics()->comm_type))

#define OFICHKERR(fncall) do {                   \
    int retval;                                  \
    if ((retval = fncall) != FI_SUCCESS) {       \
      chpl_internal_error(fi_strerror(retval));  \
    }                                            \
  } while (0)

#endif
