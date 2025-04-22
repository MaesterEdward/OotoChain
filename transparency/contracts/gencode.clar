;; Decentralized Fact Verification Protocol - Stage 1
;; A basic implementation of a blockchain-based system for verifying news facts

;; Constants
(define-constant ERR-NOT-PROTOCOL-EDITOR (err u1))
(define-constant ERR-PROTOCOL-SUSPENDED (err u2))
(define-constant ERR-INVALID-CLAIM (err u3))
(define-constant ERR-CLAIM-ALREADY-VERIFIED (err u4))
(define-constant ERR-INCORRECT-VERIFICATION-PROOF (err u5))

;; Data Variables
(define-data-var protocol-editor principal tx-sender)
(define-data-var protocol-status bool false)
(define-data-var latest-ledger-block uint u0)

;; Claim Structure
(define-map news-claims
    uint
    {
        headline: (string-utf8 256),
        truth-hash: (buff 32),      
        verification-time: uint,    
        bounty: uint,
        verified: bool
    }
)

;; Journalist Performance Tracking
(define-map journalist-records
    principal
    {
        active-claim: uint,
        total-verified: uint
    }
)

;; Authorization
(define-private (is-editor)
    (is-eq tx-sender (var-get protocol-editor)))

;; Block Height Management
(define-public (update-ledger-block (new-block uint))
    (begin
        (asserts! (is-editor) ERR-NOT-PROTOCOL-EDITOR)
        (asserts! (>= new-block (var-get latest-ledger-block)) ERR-NOT-PROTOCOL-EDITOR)
        (var-set latest-ledger-block new-block)
        (ok true)))

;; Protocol Management Functions
(define-public (initiate-protocol)
    (begin
        (asserts! (is-editor) ERR-NOT-PROTOCOL-EDITOR)
        (var-set protocol-status true)
        (ok true)))

(define-public (publish-claim
    (claim-id uint)
    (headline (string-utf8 256))
    (truth-hash (buff 32))
    (verification-time uint)
    (bounty uint))
    (begin
        (asserts! (is-editor) ERR-NOT-PROTOCOL-EDITOR)
        (asserts! (>= verification-time (var-get latest-ledger-block)) ERR-NOT-PROTOCOL-EDITOR)
        
        (map-set news-claims claim-id
            {
                headline: headline,
                truth-hash: truth-hash,
                verification-time: verification-time,
                bounty: bounty,
                verified: false
            })
        (ok true)))

;; Verification Functions
(define-public (submit-verification
    (claim-id uint)
    (evidence-proof (buff 32)))
    (let (
        (claim (unwrap! (map-get? news-claims claim-id) ERR-INVALID-CLAIM))
        (current-block (var-get latest-ledger-block))
        )
        ;; Check claim availability
        (asserts! (var-get protocol-status) ERR-PROTOCOL-SUSPENDED)
        (asserts! (>= current-block (get verification-time claim)) ERR-NOT-PROTOCOL-EDITOR)
        (asserts! (not (get verified claim)) ERR-CLAIM-ALREADY-VERIFIED)
        
        ;; Verify evidence proof
        (if (is-eq evidence-proof (get truth-hash claim))
            (begin
                ;; Update claim status
                (map-set news-claims claim-id
                    (merge claim {verified: true}))
                
                ;; Update journalist record
                (match (map-get? journalist-records tx-sender)
                    journalist (map-set journalist-records tx-sender
                        (merge journalist {
                            active-claim: claim-id,
                            total-verified: (+ (get total-verified journalist) u1)
                        }))
                    (map-set journalist-records tx-sender
                        {
                            active-claim: claim-id,
                            total-verified: u1
                        })
                )
                
                ;; Distribute bounty
                (try! (stx-transfer? (get bounty claim) (var-get protocol-editor) tx-sender))
                
                (ok true))
            ERR-INCORRECT-VERIFICATION-PROOF)))

;; Read-only functions
(define-read-only (get-claim-headline (claim-id uint))
    (match (map-get? news-claims claim-id)
        claim (ok (get headline claim))
        ERR-INVALID-CLAIM))

(define-read-only (get-journalist-profile (journalist principal))
    (map-get? journalist-records journalist))

(define-read-only (get-current-block)
    (var-get latest-ledger-block))

(define-read-only (get-protocol-status)
    (var-get protocol-status))