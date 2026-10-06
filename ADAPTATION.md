# Launch 2 adaptation

Launch admission remains blocked. The requested contracts are `FrenArtChunk3`, then
`FrenArtChunk4`, with no constructor arguments and zero deployment value. Both already
have nonpayable, argument-free constructors, no owner, and no initialization step.

The brief requires their exact STOP-prefixed art bytes and hashes. The supplied
protected floor nevertheless scans past STOP and rejects 234 positions in chunk 4.
Changing the constructor alone cannot change this result while preserving the returned
runtime. Repacking the art, adding a value guard, changing the index/renderer, or
weakening the protected check would violate the requested scope. No such changes
were made. Admission needs an upstream resolution of this conflict before launch;
passing this repository's tests does not mean the protected floor passes.

## Changes

- `test/FrenArtLaunch2.t.sol`: added CREATE2 deployment checks in the requested order,
  without constructor arguments; pinned runtime hashes and sizes; verified factory
  address predictions, EIP-170/EIP-3860 size limits, and constructor rejection of ETH.
  Added explicit reproductions of the chunk 4 and chunk 7 admission blockers and the
  existing STOP runtime's ETH behavior. Tests that reproduce rejection deliberately
  assert its presence; they do not replace the protected floor.
- `test/FrenRenderer.t.sol`: corrected deployment gas accounting for the reproduced
  gas-test finding. Replaced the undercounted `gasleft()` measurements with
  `21,000 + 32,000 * contractCount + 200 * deployedRuntimeBytes + 16 * initcodeBytes
  + 2,000,000`. The last term is an explicit per-launch budget for constructor
  execution, CREATE2 hashing, memory/copying, calldata framing and factory bookkeeping.
  The existing assertion requires this budget to fit under 95% of 2^24 gas.
  Runtime lengths come from deployed code, because the compiler's nominal runtime
  artifact does not represent the art returned by the constructors. This is a
  conservative size-based budget for the fixed contracts, not a measurement or a
  proof of the deployment service's distinct gas ceiling; its actual transaction
  still needs simulation.
- `README.md`: added the admission status and a link to this record.
- `ADAPTATION.md`: this change record and audit disposition, as required by the brief.

Production sources, generated data, hashes, configuration, and dependencies are
unchanged. No token, owner, proxy, initializer, deployment script, or launch manifest
was added. The manifest belongs to the subsequent assignment.

## Imported audit disposition

| Finding ID | Reproduction and disposition |
| --- | --- |
| `b7f5588e434686a426c5280a6bc4e6ad7823f9e1ff69b33203c2e4c90aa247e2` | Reproduced: chunk 4 has 234 rejected positions, beginning at runtime offset 3912 (`0xf4`). Chunk 3 has none. The supplied proof and unmodified protected floor both fail. Unresolved because changing the required art bytes is expressly forbidden. Execution stops at byte zero; these are unreachable data bytes. |
| `8a219c22de53cac130773e2e2aa1cac3d70e0fdd848a01598da4153d95766b8a` | Reproduced: chunk 7 has 14 rejected positions, first at offset 7671 (`0xf2`). It belongs to launch 3. Its suggested regeneration would also alter hashes/renderer outside this exact-art launch; left unchanged and covered by a reproduction test. |
| `2069d27643a27d09c89aac3090555062ce521eab79762d51df59a51598cb2a35` | Reproduced: the original test reported 940,916 gas for launch 2, excluding the 8,803,600 gas needed just to deposit its 44,018 runtime bytes. Replaced that measurement with an explicit deployment gas budget; no contract change was required. |
| `13db2d0c0ec8708560f6327f37f0e028948c0de0848b6875e6261b4490a272c5` | Reproduced for both launch-2 chunks: a call carrying 1 ETH and `0xdeadbeef` succeeds with empty return data; subsequent calls cannot withdraw it. This is the audit's stated trust note for STOP data contracts. Preserved as required; a rejection stub would change the pinned runtime. Do not send ETH to chunk addresses. Nonpayable constructors still reject deployment value. |
| `594a1ed211c9186e8138b0c65f777c1effcf710a47f98f6a1a6a9b23a44cbfda` | Informational coverage, not a defect to fix. Reconfirmed argument-free nonpayable constructors, runtime/initcode sizes, STOP prefix, and exact index hashes. The original six renderer tests pass. This adaptation does not claim a new full security audit. |

No substantive imported finding failed to reproduce. The preserved findings above
remain open or documented limitations; they are not reported as fixed.

## Preserved launch artifacts

| Contract | Runtime bytes | Initcode bytes (solc 0.8.26) | Runtime keccak256 |
| --- | ---: | ---: | --- |
| `FrenArtChunk3` | 23,479 | 28,320 | `d73ecfd95e853d3bf20224d02e30889477ac2627bc1970c5e6b0ca5ef202c9a8` |
| `FrenArtChunk4` | 20,539 | 24,814 | `4412839e8ffb01f255ce07ec70fc6c55a67a78f4365ae2a71eaa4f4d8645a5aa` |

## Checks

- Baseline: `forge build` succeeded; all six original project tests passed.
- Supplied audit proof, copied into scratch: failed with
  `FrenArtChunk4 runtime has forbidden opcode bytes: 234 != 0`, as reported.
- Supplied protected floor, copied unchanged into scratch and given the compiled
  creation code for chunks 3 and 4, factory, salts, and correct CREATE2 predictions:
  deployment succeeded, then the runtime test failed with `forbidden application opcode`.
  Temporary failing reproductions are removed from test discovery after checking;
  the delivered tests retain the evidence without claiming admission succeeds.
- No broadcast, external RPC, keys, downloaded dependencies, Slither, or Mythril were used.

- Final `forge build`: passed with the project's unchanged configuration, solc 0.8.26
  and Forge 1.8.3. Existing renderer lint warnings remain; there are no compile errors.
- Final `forge test -vv`: **11 passed, 0 failed** (the six original tests, including
  the corrected gas budget, and five new launch/audit regression tests).
- `forge test --isolate --match-test
  'test_(LaunchesFitTransactions|Launch2.*|ExactLaunch2.*|Chunk7.*)' -vv`:
  **6 passed, 0 failed**. The analytic budgets are identical in both modes:
  12,622,872 / 11,738,744 / 15,536,192 gas for launches 1 / 2 / 3, including the
  2M execution allowance, each below 15,938,355 gas (95% of 2^24, rounded down).
- SHA-256 checks against the initial files confirm that `src/FrenArtChunks.sol`,
  `src/FrenArtIndex.sol`, and `src/FrenRenderer.sol` are byte-for-byte unchanged.
  `git diff --check` passed. Only the four files listed under Changes were modified
  or added for delivery.
