# Design Review: Nova TEE Platform

This document contains a line-by-line review and suggestions for the [DESIGN.md](./DESIGN.md) document (Version 2.1).

## Structural & Architectural Suggestions

### 1. App Identity Stability (Lines 80-92)
**Current Design**: `AppID = keccak256(pcr0, pcr1, pcr2)`
**Observation**: Any code change (even a minor patch) results in a new PCR set, and thus a new `AppID`. This breaks identity continuity for users.
**Suggestion**: 
- Introduce a stable `AppID` (e.g., `keccak256(AppName, DeveloperAddr)`) that maps to a **list of valid PCR sets**.
- This allows apps to upgrade their enclave code (changing PCRs) without changing their on-chain identity.

### 2. ZK Prover Specificity (Lines 304-307)
**Current Text**: "ZKProver can be RISC Zero or Succinct SP1"
**Observation**: This is ambiguous for a system design.
**Suggestion**: 
- Explicitly define an `IZKProver` interface in the contracts.
- Specify which prover is supported in the initial release (v1.0) and if the system supports pluggable provers dynamically.

### 3. Attestation Validity Window (Lines 353-355)
**Current Design**: 5-minute validity window.
**Observation**: ZK proof generation for complex circuits can take several minutes. If the prover queue is full or generation is slow, valid attestations might expire before on-chain verification.
**Suggestion**: 
- Make the validity window **configurable** or increase the default (e.g., to 15-30 minutes).
- Alternatively, use the timestamp of *proof generation* (verified by the ZK circuit) rather than just the attestation timestamp, provided the proof generation itself is timely.

### 4. Gas Cost Optimization (Lines 799-802)
**Current Estimate**: `activateApp` ~347k gas.
**Observation**: This is relatively high (~$10-20 on mainnet at moderate gas).
**Suggestion**: 
- Prioritize **L2 deployment** (Optimism/Arbitrum) as the primary target, not just a "Future Enhancement".
- Consider **batch activation**: allowing the platform to submit multiple proofs in one transaction to amortize the base transaction cost.

### 5. Platform Decentralization (Lines 591-620)
**Current Status**: "High-Severity Issue" with "Recommended Enhancement".
**Observation**: The reliance on a single `PLATFORM_ROLE` is a significant centralization risk.
**Suggestion**: 
- Move the **Multi-Platform Support** proposal (Lines 605-620) from "Potential Issues" to the **Core Architecture**.
- It is critical enough that it should be part of the planned v2.x roadmap, not just a "recommendation".

### 6. Heartbeat Mechanism (Lines 132-144)
**Current Design**: Platform monitors and updates heartbeat.
**Observation**: If the platform goes offline, all apps could eventually be marked inactive.
**Suggestion**: 
- **Self-Heartbeat**: Allow the `Operator` (the enclave itself) to submit a heartbeat transaction directly, bypassing the platform. This ensures liveness even if the platform infrastructure is down.

## Minor / Editorial Suggestions

- **Line 378**: `instance.walletAddress = ethAddress;` - Clarify if `ethAddress` here refers to the *operator's* address or the *wallet's* address. It seems to be the operator's address initially, but the comment says "Updated when wallet deployed".
- **Line 402**: `validate paymaster` - In EIP-4337, the EntryPoint calls `validatePaymasterUserOp`. Use the precise function name for clarity.
- **Terminology**: Ensure consistent distinction between **AppContract** (the user's business logic contract) and **AppInstance** (the specific running enclave instance).

## Diagram Updates
- **Suggestion**: Replace the ASCII diagrams in `DESIGN.md` with links to the newly created `design-mermaid.md` to improve maintainability and readability.
