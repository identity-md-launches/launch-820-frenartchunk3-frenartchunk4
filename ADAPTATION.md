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

## Revision: admission finding and reviewer responses

The sections above describe the previously accepted work. This revision preserves
that implementation, its tests, and the exact generated art. Its only delivered
changes are this revision record and `.imd-responses.json`, which answers the
reopened finding and all five imported audit entries using the required schema.

Reopened finding
`00f0e0b8a1fb03d66b55ba063f934290056a42d20fd936df646527d1cb904390`
reproduces. The response is **disputed as a required local repair**, not dismissed
as non-reproducible: the proof demands zero scanner-visible rejected bytes in the
same runtime the task expressly requires us to leave unchanged. It observes a
real admission failure. It cannot pass for these exact bytes under the supplied
policy. A constructor change returning identical runtime cannot affect that result.

No upstream admission-policy implementation is present to change. The supplied
protected test is a pinned input, not an editable policy implementation. Before
launch, the policy owner must resolve admission of these exact STOP-prefixed data
contracts and provide the corresponding approved protected check and proof. A
possible decision is a narrowly scoped exception for the exact hashes above,
verified against their leading STOP; this is a proposal, not an implemented or
approved exception. Repacking the art or changing the renderer requires a separate
scope decision. No proof, protected input, art, hash, or production source was
changed, and admission is still blocked.

Revision checks, using Forge 1.8.3 and solc 0.8.26:

- Copied both supplied proofs unchanged under `test/scratch/` and ran
  `forge test --offline --out test/scratch/out --cache-path test/scratch/cache
  --match-path 'test/scratch/Proof_*.t.sol' -vv`. Both failed at chunk 4 with
  `234 != 0`; chunk 3 had zero rejected positions, and chunk 4's first was 3912.
- Copied the protected test unchanged and supplied the compiled creation code,
  factory `0x1111111111111111111111111111111111111111`, chain ID 1, salts 3 and 4
  encoded as bytes32, and calculated CREATE2 addresses
  `0xb9443776b5f99a0fd9d999bd7ead039c20ff130e` and
  `0xd62d5be0ddf691e59ae0cce61bda6894aa9fe146`. Deployment succeeded for both;
  the check failed with `forbidden application opcode`. With count 1 and chunk 3
  alone, the same protected test passed. No transaction was broadcast.
- After reproduction, kept the exact proof bytes as scratch `.fixture` files and
  removed the temporary protected `.t.sol` copy from discovery. This does not make
  the proofs pass; it allows the requested ordinary project checks to run separately.
- `forge build` and `forge test`: passed, with all 11 accepted tests passing.
  These include chunk 7's 14 rejected positions, the ETH-sink behavior, constructor
  value rejection, exact runtime/hash checks, and renderer equivalence.
- `forge test --isolate --match-test test_LaunchesFitTransactions -vv`: passed.
  The default and isolated launch budgets remain 12,622,872 / 11,738,744 /
  15,536,192 gas. The imported gas finding was already fixed by the accepted work;
  it required no further code changes in this revision.
- Verified the response JSON has exactly one entry for every supplied finding,
  checked the diff for whitespace errors, and compared source/test/configuration
  fingerprints to the revision's starting tree. Those files remain unchanged.

## Revision: settlement finding 533e8020b8a9

The current reopened finding
`533e8020b8a9690fe07a444508865a783aaecdc54860334a652acbf853b9ff16`
reproduces and remains an admission blocker. It is disputed only as a required
local repair: zero rejected positions and the explicitly required unchanged art
bytes cannot both hold under the supplied scanner. The preceding policy/scope
decision is still required; no approved exception was supplied in this revision.

Changes in this revision:

- `.imd-responses.json`: added the required machine-readable answer for the reopened
  finding and each of the five imported audit entries. The responses distinguish
  reproduced but disputed repairs, the gas correction already present in the
  starting tree, and the informational coverage entry.
- `ADAPTATION.md`: added this revision's evidence and disposition. No implementation,
  generated art, test, configuration, dependency, manifest, or pinned input changed.

Checks with Forge 1.8.3 and solc 0.8.26:

- Both supplied proofs were copied unchanged under `test/scratch/` and run with
  `forge test --offline --out test/scratch/out --cache-path test/scratch/cache
  --match-path 'test/scratch/Proof_*.t.sol' -vv`. Both fail at chunk 4 with
  `234 != 0`; the settlement proof logs the first rejected position at 3912.
- The unchanged protected test was run with the factory, chain ID, compiled
  creation code, salts and predicted addresses recorded in the preceding revision.
  Both constructors succeed, then count 2 fails with `forbidden application opcode`;
  count 1 (chunk 3 alone) passes. The proofs and protected copy were then retained
  as scratch `.fixture` files so the ordinary project suite can run separately.
  This does not resolve or hide the failed admission checks.
- An independent scan of the generated literals confirms chunk 3 has zero rejected
  positions, chunk 4 has 234, and chunk 7 has 14 (first at 7671).
- `forge build` and `forge test -vv` pass; all 11 existing tests pass, including
  exact runtime/hash checks, constructor value rejection, the documented ETH sink,
  chunk 7's reproduced blocker and renderer equivalence.
- `forge test --isolate --match-test test_LaunchesFitTransactions -vv` passes with
  the same budgets as the default run: 12,622,872 / 11,738,744 / 15,536,192 gas.
  The reported 940,916 gas undercount no longer reproduces in the accepted test.
- Response IDs/schema, source/test/configuration/dependency fingerprints and
  `git diff --check` were checked. No RPC, broadcast, keys, new dependency,
  Slither or Mythril were used.

The reopened report describes another tree with 25 tests and a launch manifest.
The supplied starting tree has 11 tests, including the existing scanner-rejection
reproductions, and no `launch.json`. Those artifacts were preserved as supplied;
this revision does not recreate another contributor's changes. Passing the project
suite does not establish launch admission, which remains blocked.
