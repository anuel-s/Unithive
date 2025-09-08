;; Fractional Real Estate Ownership Platform
;; Smart contract for tokenized real estate with governance and income distribution

;; Error constants
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-INVALID-INPUT (err u102))
(define-constant ERR-INACTIVE-PROPERTY (err u103))
(define-constant ERR-INSUFFICIENT-BALANCE (err u104))
(define-constant ERR-NO-INCOME-AVAILABLE (err u105))
(define-constant ERR-VOTING-ENDED (err u106))
(define-constant ERR-VOTING-IN-PROGRESS (err u107))
(define-constant ERR-PROPOSAL-FAILED (err u108))
(define-constant ERR-ALREADY-EXECUTED (err u109))

;; Contract owner
(define-constant CONTRACT-ADMIN tx-sender)

;; Property registry
(define-map property-registry
  { property-id: uint }
  {
    name: (string-utf8 128),
    location: (string-utf8 128),
    total-supply: uint,
    price-per-token: uint,
    is-active: bool,
    property-admin: principal,
    creation-block: uint
  }
)

;; Token balances for each property
(define-map token-balances
  { property-id: uint, holder: principal }
  { balance: uint }
)

;; Issued token tracking
(define-map token-supply
  { property-id: uint }
  { issued-amount: uint }
)

;; Income distribution data
(define-map revenue-pool
  { property-id: uint }
  {
    total-revenue: uint,
    revenue-per-token: uint,
    last-update: uint
  }
)

;; Income claim tracking
(define-map claim-history
  { property-id: uint, claimant: principal }
  {
    claimed-per-token: uint,
    last-claim-block: uint
  }
)

;; Governance proposal data
(define-map governance-registry
  { property-id: uint, proposal-id: uint }
  {
    title: (string-utf8 128),
    description: (string-utf8 256),
    creator: principal,
    start-block: uint,
    end-block: uint,
    yes-votes: uint,
    no-votes: uint,
    is-executed: bool,
    category: (string-ascii 32)
  }
)

;; Voting records
(define-map voting-records
  { property-id: uint, proposal-id: uint, voter: principal }
  { support: bool, weight: uint }
)

;; ID counters
(define-data-var property-counter uint u1)
(define-map proposal-counter { property-id: uint } { next-id: uint })

;; Helper: Check if caller is contract admin
(define-private (is-admin)
  (is-eq tx-sender CONTRACT-ADMIN)
)

;; Helper: Check if caller is property admin
(define-private (is-property-owner (property-id uint))
  (match (map-get? property-registry { property-id: property-id })
    prop (is-eq tx-sender (get property-admin prop))
    false
  )
)

;; Helper: Get property safely
(define-private (fetch-property (property-id uint))
  (ok (unwrap! (map-get? property-registry { property-id: property-id }) ERR-NOT-FOUND))
)

;; Helper: Get token balance
(define-private (get-balance (property-id uint) (account principal))
  (default-to u0 
    (get balance (map-get? token-balances { property-id: property-id, holder: account }))
  )
)

;; Create a new tokenized property
(define-public (register-property 
                (name (string-utf8 128))
                (location (string-utf8 128))
                (total-supply uint)
                (price-per-token uint))
  (let ((new-id (var-get property-counter)))
    ;; Input validation
    (asserts! (is-admin) ERR-UNAUTHORIZED)
    (asserts! (> total-supply u0) ERR-INVALID-INPUT)
    (asserts! (> price-per-token u0) ERR-INVALID-INPUT)
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len location) u0) ERR-INVALID-INPUT)
    
    ;; Register property
    (map-set property-registry
      { property-id: new-id }
      {
        name: name,
        location: location,
        total-supply: total-supply,
        price-per-token: price-per-token,
        is-active: true,
        property-admin: tx-sender,
        creation-block: block-height
      }
    )
    
    ;; Initialize related data
    (map-set token-supply { property-id: new-id } { issued-amount: u0 })
    (map-set revenue-pool 
      { property-id: new-id } 
      { total-revenue: u0, revenue-per-token: u0, last-update: u0 }
    )
    (map-set proposal-counter { property-id: new-id } { next-id: u0 })
    
    ;; Update counter
    (var-set property-counter (+ new-id u1))
    (ok new-id)
  )
)

;; Purchase property tokens
(define-public (purchase-tokens (property-id uint) (amount uint))
  (let (
    (property-data (try! (fetch-property property-id)))
    (purchase-cost (* amount (get price-per-token property-data)))
    (current-supply (get issued-amount (unwrap! (map-get? token-supply { property-id: property-id }) ERR-NOT-FOUND)))
    (buyer-balance (get-balance property-id tx-sender))
  )
    ;; Validation checks
    (asserts! (get is-active property-data) ERR-INACTIVE-PROPERTY)
    (asserts! (> amount u0) ERR-INVALID-INPUT)
    (asserts! (<= (+ current-supply amount) (get total-supply property-data)) ERR-INSUFFICIENT-BALANCE)
    
    ;; Process payment
    (try! (stx-transfer? purchase-cost tx-sender (as-contract tx-sender)))
    
    ;; Update token balance
    (map-set token-balances
      { property-id: property-id, holder: tx-sender }
      { balance: (+ buyer-balance amount) }
    )
    
    ;; Update supply counter
    (map-set token-supply
      { property-id: property-id }
      { issued-amount: (+ current-supply amount) }
    )
    
    ;; Initialize claim tracking for new holders
    (if (is-eq buyer-balance u0)
      (map-set claim-history
        { property-id: property-id, claimant: tx-sender }
        {
          claimed-per-token: (get revenue-per-token (unwrap-panic (map-get? revenue-pool { property-id: property-id }))),
          last-claim-block: block-height
        }
      )
      true
    )
    
    (ok amount)
  )
)

;; Add revenue to property pool
(define-public (deposit-revenue (property-id uint) (amount uint))
  (let (
    (property-data (try! (fetch-property property-id)))
    (pool-data (unwrap! (map-get? revenue-pool { property-id: property-id }) ERR-NOT-FOUND))
    (current-supply (get issued-amount (unwrap! (map-get? token-supply { property-id: property-id }) ERR-NOT-FOUND)))
    (revenue-increment (if (> current-supply u0) (/ amount current-supply) u0))
  )
    ;; Authorization and validation
    (asserts! (get is-active property-data) ERR-INACTIVE-PROPERTY)
    (asserts! (is-property-owner property-id) ERR-UNAUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-INPUT)
    
    ;; Transfer revenue to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Update revenue pool
    (map-set revenue-pool
      { property-id: property-id }
      {
        total-revenue: (+ (get total-revenue pool-data) amount),
        revenue-per-token: (+ (get revenue-per-token pool-data) revenue-increment),
        last-update: block-height
      }
    )
    
    (ok amount)
  )
)

;; Claim accumulated revenue
(define-public (withdraw-revenue (property-id uint))
  (let (
    (property-data (try! (fetch-property property-id)))
    (pool-data (unwrap! (map-get? revenue-pool { property-id: property-id }) ERR-NOT-FOUND))
    (holder-balance (get-balance property-id tx-sender))
    (claim-data (default-to 
      { claimed-per-token: u0, last-claim-block: u0 }
      (map-get? claim-history { property-id: property-id, claimant: tx-sender })
    ))
    (unclaimed-per-token (- (get revenue-per-token pool-data) (get claimed-per-token claim-data)))
    (withdrawal-amount (* holder-balance unclaimed-per-token))
  )
    ;; Validation
    (asserts! (get is-active property-data) ERR-INACTIVE-PROPERTY)
    (asserts! (> holder-balance u0) ERR-INSUFFICIENT-BALANCE)
    (asserts! (> withdrawal-amount u0) ERR-NO-INCOME-AVAILABLE)
    
    ;; Update claim record
    (map-set claim-history
      { property-id: property-id, claimant: tx-sender }
      {
        claimed-per-token: (get revenue-per-token pool-data),
        last-claim-block: block-height
      }
    )
    
    ;; Transfer revenue to claimer
    (try! (as-contract (stx-transfer? withdrawal-amount tx-sender tx-sender)))
    (ok withdrawal-amount)
  )
)

;; Submit governance proposal
(define-public (submit-proposal
                (property-id uint)
                (title (string-utf8 128))
                (description (string-utf8 256))
                (voting-duration uint)
                (category (string-ascii 32)))
  (let (
    (property-data (try! (fetch-property property-id)))
    (holder-balance (get-balance property-id tx-sender))
    (minimum-tokens (/ (get total-supply property-data) u20)) ;; 5% requirement
    (counter-data (unwrap! (map-get? proposal-counter { property-id: property-id }) ERR-NOT-FOUND))
    (new-proposal-id (get next-id counter-data))
  )
    ;; Validation
    (asserts! (get is-active property-data) ERR-INACTIVE-PROPERTY)
    (asserts! (>= holder-balance minimum-tokens) ERR-INSUFFICIENT-BALANCE)
    (asserts! (> voting-duration u0) ERR-INVALID-INPUT)
    (asserts! (> (len title) u0) ERR-INVALID-INPUT)
    
    ;; Create proposal
    (map-set governance-registry
      { property-id: property-id, proposal-id: new-proposal-id }
      {
        title: title,
        description: description,
        creator: tx-sender,
        start-block: block-height,
        end-block: (+ block-height voting-duration),
        yes-votes: u0,
        no-votes: u0,
        is-executed: false,
        category: category
      }
    )
    
    ;; Update counter
    (map-set proposal-counter { property-id: property-id } { next-id: (+ new-proposal-id u1) })
    (ok new-proposal-id)
  )
)

;; Cast vote on proposal
(define-public (cast-vote (property-id uint) (proposal-id uint) (support bool))
  (let (
    (property-data (try! (fetch-property property-id)))
    (proposal-data (unwrap! (map-get? governance-registry { property-id: property-id, proposal-id: proposal-id }) ERR-NOT-FOUND))
    (voter-balance (get-balance property-id tx-sender))
    (previous-vote (map-get? voting-records { property-id: property-id, proposal-id: proposal-id, voter: tx-sender }))
  )
    ;; Validation
    (asserts! (get is-active property-data) ERR-INACTIVE-PROPERTY)
    (asserts! (> voter-balance u0) ERR-INSUFFICIENT-BALANCE)
    (asserts! (< block-height (get end-block proposal-data)) ERR-VOTING-ENDED)
    (asserts! (not (get is-executed proposal-data)) ERR-ALREADY-EXECUTED)
    
    ;; Remove previous vote if exists
    (match previous-vote
      old-vote 
        (map-set governance-registry
          { property-id: property-id, proposal-id: proposal-id }
          (if (get support old-vote)
            (merge proposal-data { yes-votes: (- (get yes-votes proposal-data) (get weight old-vote)) })
            (merge proposal-data { no-votes: (- (get no-votes proposal-data) (get weight old-vote)) })
          )
        )
      true
    )
    
    ;; Record new vote
    (map-set voting-records
      { property-id: property-id, proposal-id: proposal-id, voter: tx-sender }
      { support: support, weight: voter-balance }
    )
    
    ;; Update proposal tallies
    (map-set governance-registry
      { property-id: property-id, proposal-id: proposal-id }
      (if support
        (merge proposal-data { yes-votes: (+ (get yes-votes proposal-data) voter-balance) })
        (merge proposal-data { no-votes: (+ (get no-votes proposal-data) voter-balance) })
      )
    )
    
    (ok true)
  )
)

;; Execute approved proposal
(define-public (execute-proposal (property-id uint) (proposal-id uint))
  (let (
    (property-data (try! (fetch-property property-id)))
    (proposal-data (unwrap! (map-get? governance-registry { property-id: property-id, proposal-id: proposal-id }) ERR-NOT-FOUND))
    (total-votes (+ (get yes-votes proposal-data) (get no-votes proposal-data)))
    (quorum-threshold (/ (get total-supply property-data) u10)) ;; 10% quorum
  )
    ;; Validation
    (asserts! (get is-active property-data) ERR-INACTIVE-PROPERTY)
    (asserts! (>= block-height (get end-block proposal-data)) ERR-VOTING-IN-PROGRESS)
    (asserts! (not (get is-executed proposal-data)) ERR-ALREADY-EXECUTED)
    (asserts! (>= total-votes quorum-threshold) ERR-PROPOSAL-FAILED)
    (asserts! (> (get yes-votes proposal-data) (get no-votes proposal-data)) ERR-PROPOSAL-FAILED)
    
    ;; Mark as executed
    (map-set governance-registry
      { property-id: property-id, proposal-id: proposal-id }
      (merge proposal-data { is-executed: true })
    )
    
    (ok true)
  )
)

;; Read-only: Get property information
(define-read-only (get-property-info (property-id uint))
  (map-get? property-registry { property-id: property-id })
)

;; Read-only: Get token balance
(define-read-only (get-token-balance (property-id uint) (account principal))
  (get-balance property-id account)
)

;; Read-only: Get proposal details
(define-read-only (get-proposal-info (property-id uint) (proposal-id uint))
  (map-get? governance-registry { property-id: property-id, proposal-id: proposal-id })
)

;; Read-only: Calculate claimable revenue
(define-read-only (calculate-claimable (property-id uint) (account principal))
  (match (map-get? revenue-pool { property-id: property-id })
    pool-data
      (let (
        (account-balance (get-balance property-id account))
        (claim-data (default-to 
          { claimed-per-token: u0, last-claim-block: u0 }
          (map-get? claim-history { property-id: property-id, claimant: account })
        ))
        (unclaimed-per-token (- (get revenue-per-token pool-data) (get claimed-per-token claim-data)))
      )
        (* account-balance unclaimed-per-token)
      )
    u0
  )
)

;; Read-only: Get total properties count
(define-read-only (get-properties-count)
  (- (var-get property-counter) u1)
)