;; Decentralized Fact Verification and Journalism Protocol
;; A blockchain-based system for verifying news facts, maintaining journalistic integrity, and rewarding accurate reporting

;; Constants
(define-constant ERR-NOT-PROTOCOL-EDITOR (err u1))
(define-constant ERR-PROTOCOL-SUSPENDED (err u2))
(define-constant ERR-INVALID-CLAIM (err u3))
(define-constant ERR-CLAIM-ALREADY-VERIFIED (err u4))
(define-constant ERR-INCORRECT-VERIFICATION-PROOF (err u5))
(define-constant ERR-VERIFICATION-PERIOD-ACTIVE (err u6))
(define-constant ERR-INSUFFICIENT-REPUTATION (err u7))
(define-constant ERR-INVALID-PARAMETER (err u8))
(define-constant ERR-CLAIM-EXISTS (err u9))
(define-constant MAX-CLAIM-ID u100) ;; Maximum allowed claim ID

;; Data Variables
(define-data-var protocol-editor principal tx-sender)
(define-data-var protocol-status bool false)
(define-data-var current-cycle uint u0)
(define-data-var credibility-threshold uint u1000000) ;; 1 STX
(define-data-var total-bounty-pool uint u0)
(define-data-var latest-ledger-block uint u0) ;; Block height tracking for verification periods

;; Claim Structure
(define-map news-claims
    uint
    {
        headline: (string-utf8 256),
        truth-hash: (buff 32),      ;; SHA256 hash of the verified factual evidence
        verification-time: uint,    ;; Verification deadline (block height)
        bounty: uint,
        verified: bool
    }
)

;; Journalist Performance Tracking
(define-map journalist-records
    principal
    {
        active-claim: uint,
        verified-claims: (list 20 uint),
        last-verification: uint,
        total-verified: uint
    }
)

;; Verification History
(define-map claim-verifications
    {claim-id: uint, journalist: principal}
    {
        submissions: uint,
        verified-at: (optional uint)
    }
)

;; Events
(define-map verification-history
    uint
    (list 10 {journalist: principal, verified-block: uint})
)

;; Authorization
(define-private (is-editor)
    (is-eq tx-sender (var-get protocol-editor)))

;; Block Height Management
(define-public (update-ledger-block (new-block uint))
    (begin
        (asserts! (is-editor) ERR-NOT-PROTOCOL-EDITOR)
        ;; Validate block is not less than current
        (asserts! (>= new-block (var-get latest-ledger-block)) ERR-INVALID-PARAMETER)
        (var-set latest-ledger-block new-block)
        (ok true)))

;; Protocol Management Functions
(define-public (initiate-protocol)
    (begin
        (asserts! (is-editor) ERR-NOT-PROTOCOL-EDITOR)
        (var-set protocol-status true)
        (var-set current-cycle u0)
        (var-set total-bounty-pool u0)
        (ok true)))

(define-public (publish-claim
    (claim-id uint)
    (headline (string-utf8 256))
    (truth-hash (buff 32))
    (verification-time uint)
    (bounty uint))
    (begin
        (asserts! (is-editor) ERR-NOT-PROTOCOL-EDITOR)
        
        ;; Validate claim-id is within acceptable range
        (asserts! (<= claim-id MAX-CLAIM-ID) ERR-INVALID-PARAMETER)
        
        ;; Check if claim already exists to prevent overwriting
        (asserts! (is-none (map-get? news-claims claim-id)) ERR-CLAIM-EXISTS)
        
        ;; Validate verification time is in the future
        (asserts! (>= verification-time (var-get latest-ledger-block)) ERR-INVALID-PARAMETER)
        
        ;; Validate truth hash is not empty
        (asserts! (> (len truth-hash) u0) ERR-INVALID-PARAMETER)
        
        ;; Validate headline is not empty
        (asserts! (> (len headline) u0) ERR-INVALID-PARAMETER)
        
        ;; Validate bounty is a positive amount
        (asserts! (> bounty u0) ERR-INVALID-PARAMETER)
        
        ;; Set the claim data
        (map-set news-claims claim-id
            {
                headline: headline,
                truth-hash: truth-hash,
                verification-time: verification-time,
                bounty: bounty,
                verified: false
            })
            
        ;; Calculate new bounty pool safely
        (let ((new-pool (+ (var-get total-bounty-pool) bounty)))
            ;; Make sure the addition doesn't overflow
            (asserts! (>= new-pool (var-get total-bounty-pool)) ERR-INVALID-PARAMETER)
            ;; Update the total bounty pool
            (var-set total-bounty-pool new-pool))
        (ok true)))

;; Journalist Registration
(define-public (register-as-journalist)
    (begin
        (asserts! (var-get protocol-status) ERR-PROTOCOL-SUSPENDED)
        ;; Require credibility threshold
        (try! (stx-transfer? (var-get credibility-threshold) tx-sender (var-get protocol-editor)))
        
        (map-set journalist-records tx-sender
            {
                active-claim: u0,
                verified-claims: (list),
                last-verification: u0,
                total-verified: u0
            })
        (ok true)))

;; Verification Functions
(define-public (submit-verification
    (claim-id uint)
    (evidence-proof (buff 32)))
    (let (
        (claim (unwrap! (map-get? news-claims claim-id) ERR-INVALID-CLAIM))
        (journalist (unwrap! (map-get? journalist-records tx-sender) ERR-INSUFFICIENT-REPUTATION))
        (current-block (var-get latest-ledger-block))
        )
        ;; Check claim availability
        (asserts! (var-get protocol-status) ERR-PROTOCOL-SUSPENDED)
        (asserts! (>= current-block (get verification-time claim)) ERR-VERIFICATION-PERIOD-ACTIVE)
        (asserts! (not (get verified claim)) ERR-CLAIM-ALREADY-VERIFIED)
        
        ;; Verify evidence proof - directly compare the hashes
        (if (is-eq evidence-proof (get truth-hash claim))
            (begin
                ;; Update claim status
                (map-set news-claims claim-id
                    (merge claim {verified: true}))
                
                ;; Update journalist record
                (map-set journalist-records tx-sender
                    (merge journalist {
                        active-claim: (+ claim-id u1),
                        verified-claims: (unwrap! (as-max-len? 
                            (append (get verified-claims journalist) claim-id) u20)
                            ERR-INVALID-CLAIM),
                        last-verification: current-block,
                        total-verified: (+ (get total-verified journalist) u1)
                    }))
                
                ;; Record verification
                (map-set claim-verifications
                    {claim-id: claim-id, journalist: tx-sender}
                    {
                        submissions: u1,
                        verified-at: (some current-block)
                    })
                
                ;; Distribute bounty
                (try! (stx-transfer? (get bounty claim) (var-get protocol-editor) tx-sender))
                
                ;; Record verification history
                (match (map-get? verification-history claim-id)
                    history (map-set verification-history claim-id
                        (unwrap! (as-max-len?
                            (append history {journalist: tx-sender, verified-block: current-block})
                            u10)
                            ERR-INVALID-CLAIM))
                    (map-set verification-history claim-id
                        (list {journalist: tx-sender, verified-block: current-block})))
                
                (ok true))
            ERR-INCORRECT-VERIFICATION-PROOF)))

;; Read-only functions
(define-read-only (get-claim-headline (claim-id uint))
    (match (map-get? news-claims claim-id)
        claim (if (>= (var-get latest-ledger-block) (get verification-time claim))
            (ok (get headline claim))
            ERR-VERIFICATION-PERIOD-ACTIVE)
        ERR-INVALID-CLAIM))

(define-read-only (get-journalist-profile (journalist principal))
    (map-get? journalist-records journalist))

(define-read-only (get-verification-history (claim-id uint))
    (map-get? verification-history claim-id))

(define-read-only (get-current-block)
    (var-get latest-ledger-block))

(define-read-only (get-protocol-metrics)
    {
        active: (var-get protocol-status),
        current-cycle: (var-get current-cycle),
        total-bounty-pool: (var-get total-bounty-pool),
        credibility-threshold: (var-get credibility-threshold),
        latest-ledger-block: (var-get latest-ledger-block)
    })

(define-public (update-credibility-threshold (new-threshold uint))
    (begin
        (asserts! (is-editor) ERR-NOT-PROTOCOL-EDITOR)
        (var-set credibility-threshold new-threshold)
        (ok true)))

(define-public (suspend-protocol)
    (begin
        (asserts! (is-editor) ERR-NOT-PROTOCOL-EDITOR)
        (var-set protocol-status false)
        (ok true)))

(define-public (advance-cycle)
    (begin
        (asserts! (is-editor) ERR-NOT-PROTOCOL-EDITOR)
        (asserts! (var-get protocol-status) ERR-PROTOCOL-SUSPENDED)
        (var-set current-cycle (+ (var-get current-cycle) u1))
        (ok true)))

(define-public (transfer-protocol-editor (new-editor principal))
    (begin
        (asserts! (is-editor) ERR-NOT-PROTOCOL-EDITOR)
        (var-set protocol-editor new-editor)
        (ok true)))