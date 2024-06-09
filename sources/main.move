module store_management::store_management {

    use sui::transfer;
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::object::{Self, UID};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};
    use std::option::{Option, none, some, is_some, contains, borrow};

    // Error codes for various error conditions
    const EInvalidTransaction: u64 = 1;
    const EInvalidItem: u64 = 2;
    const EDispute: u64 = 3;
    const EAlreadyResolved: u64 = 4;
    const ENotStore: u64 = 5;
    const EInvalidWithdrawal: u64 = 6;
    const EDeadlinePassed: u64 = 7;
    const EInsufficientEscrow: u64 = 8;
    const EInsufficientFunds: u64 = 9;

    // Struct definitions

    /// Represents a transaction in the store.
    struct Transaction has key, store {
        id: UID,                          // Unique identifier for the transaction
        customer: address,                // Address of the customer
        item: vector<u8>,                 // Item being transacted
        quantity: u64,                    // Quantity of the item
        price: u64,                       // Price of the item in points
        escrow: Balance<SUI>,             // Escrow balance for the transaction
        dispute: bool,                    // Dispute status
        rating: Option<u64>,              // Rating given by the customer
        status: vector<u8>,               // Status of the transaction
        store: Option<address>,           // Address of the store (initially None, set when accepted)
        transactionFulfilled: bool,       // Whether the transaction is fulfilled
        created_at: u64,                  // Timestamp when the transaction was created
        deadline: u64,                    // Deadline for the transaction
    }

    /// Represents a review for an item.
    struct ItemReview has key, store {
        id: UID,                          // Unique identifier for the review
        customer: address,                // Address of the customer who reviewed
        review: vector<u8>,               // Review text
    }

    // Event logging structure
    struct TransactionEvent has key {
        id: UID,                          // Unique identifier for the event
        transaction_id: UID,              // Identifier of the related transaction
        action: vector<u8>,               // Description of the action performed
        timestamp: u64,                   // Timestamp when the action was performed
    }

    // Accessors to retrieve transaction details

    /// Retrieves the item being transacted.
    public entry fun get_item(transaction: &Transaction): vector<u8> {
        transaction.item
    }

    /// Retrieves the price of the transaction.
    public entry fun get_transaction_price(transaction: &Transaction): u64 {
        transaction.price
    }

    /// Retrieves the status of the transaction.
    public entry fun get_transaction_status(transaction: &Transaction): vector<u8> {
        transaction.status
    }

    /// Retrieves the deadline for the transaction.
    public entry fun get_transaction_deadline(transaction: &Transaction): u64 {
        transaction.deadline
    }

    // Public - Entry functions

    /// Creates a new transaction in the store.
    public entry fun create_transaction(item: vector<u8>, quantity: u64, price: u64, clock: &Clock, duration: u64, open: vector<u8>, ctx: &mut TxContext) {
        let transaction_id = object::new(ctx);
        let deadline = clock::timestamp_ms(clock) + duration;
        transfer::share_object(Transaction {
            id: transaction_id,
            customer: tx_context::sender(ctx),
            store: none(), // Set to an initial value, can be updated later
            item: item,
            quantity: quantity,
            rating: none(),
            status: open,
            price: price,
            escrow: balance::zero(),
            transactionFulfilled: false,
            dispute: false,
            created_at: clock::timestamp_ms(clock),
            deadline: deadline,
        });

        emit_event(TransactionEvent {
            id: object::new(ctx),
            transaction_id: transaction_id,
            action: b"Transaction Created".to_vec(),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Store accepts the transaction.
    public entry fun accept_transaction(transaction: &mut Transaction, ctx: &mut TxContext) {
        assert!(!is_some(&transaction.store), EInvalidTransaction);
        transaction.store = some(tx_context::sender(ctx));

        emit_event(TransactionEvent {
            id: object::new(ctx),
            transaction_id: transaction.id,
            action: b"Transaction Accepted".to_vec(),
            timestamp: clock::timestamp_ms(ctx),
        });
    }

    /// Fulfills the transaction.
    public entry fun fulfill_transaction(transaction: &mut Transaction, clock: &Clock, ctx: &mut TxContext) {
        assert!(contains(&transaction.store, &tx_context::sender(ctx)), EInvalidItem);
        assert!(clock::timestamp_ms(clock) < transaction.deadline, EDeadlinePassed);
        transaction.transactionFulfilled = true;

        emit_event(TransactionEvent {
            id: object::new(ctx),
            transaction_id: transaction.id,
            action: b"Transaction Fulfilled".to_vec(),
            timestamp: clock::timestamp_ms(ctx),
        });
    }

    /// Marks the transaction as complete.
    public entry fun mark_transaction_complete(transaction: &mut Transaction, ctx: &mut TxContext) {
        assert!(contains(&transaction.store, &tx_context::sender(ctx)), ENotStore);
        transaction.transactionFulfilled = true;

        emit_event(TransactionEvent {
            id: object::new(ctx),
            transaction_id: transaction.id,
            action: b"Transaction Completed".to_vec(),
            timestamp: clock::timestamp_ms(ctx),
        });
    }

    /// Raises a dispute for the transaction.
    public entry fun dispute_transaction(transaction: &mut Transaction, ctx: &mut TxContext) {
        assert!(transaction.customer == tx_context::sender(ctx), EDispute);
        transaction.dispute = true;

        emit_event(TransactionEvent {
            id: object::new(ctx),
            transaction_id: transaction.id,
            action: b"Dispute Raised".to_vec(),
            timestamp: clock::timestamp_ms(ctx),
        });
    }

    /// Resolves a dispute for the transaction.
    public entry fun resolve_dispute(transaction: &mut Transaction, resolved: bool, ctx: &mut TxContext) {
        assert!(transaction.customer == tx_context::sender(ctx), EDispute);
        assert!(transaction.dispute, EAlreadyResolved);
        assert!(is_some(&transaction.store), EInvalidTransaction);
        let escrow_amount = balance::value(&transaction.escrow);
        let escrow_coin = coin::take(&mut transaction.escrow, escrow_amount, ctx);
        if (resolved) {
            let store = *borrow(&transaction.store);
            // Transfer points to the store
            transfer::public_transfer(escrow_coin, store);
        } else {
            // Refund points to the customer
            transfer::public_transfer(escrow_coin, transaction.customer);
        };

        // Reset transaction state
        transaction.store = none();
        transaction.transactionFulfilled = false;
        transaction.dispute = false;

        emit_event(TransactionEvent {
            id: object::new(ctx),
            transaction_id: transaction.id,
            action: b"Dispute Resolved".to_vec(),
            timestamp: clock::timestamp_ms(ctx),
        });
    }

    /// Releases payment to the store after the transaction is fulfilled.
    public entry fun release_payment(transaction: &mut Transaction, clock: &Clock, review: vector<u8>, ctx: &mut TxContext) {
        assert!(transaction.customer == tx_context::sender(ctx), ENotStore);
        assert!(transaction.transactionFulfilled && !transaction.dispute, EInvalidItem);
        assert!(clock::timestamp_ms(clock) > transaction.deadline, EDeadlinePassed);
        assert!(is_some(&transaction.store), EInvalidTransaction);
        let store = *borrow(&transaction.store);
        let escrow_amount = balance::value(&transaction.escrow);
        assert!(escrow_amount > 0, EInsufficientEscrow); // Ensure there are enough points in escrow
        let escrow_coin = coin::take(&mut transaction.escrow, escrow_amount, ctx);
        // Transfer points to the store
        transfer::public_transfer(escrow_coin, store);

        // Create a new item review
        let itemReview = ItemReview {
            id: object::new(ctx),
            customer: tx_context::sender(ctx),
            review: review,
        };

        // Change accessibility of item review
        transfer::public_transfer(itemReview, tx_context::sender(ctx));

        // Reset transaction state
        transaction.store = none();
        transaction.transactionFulfilled = false;
        transaction.dispute = false;

        emit_event(TransactionEvent {
            id: object::new(ctx),
            transaction_id: transaction.id,
            action: b"Payment Released".to_vec(),
            timestamp: clock::timestamp_ms(ctx),
        });
    }

    /// Adds more points to the transaction escrow.
    public entry fun add_funds_to_escrow(transaction: &mut Transaction, amount: Coin<SUI>, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == transaction.customer, ENotStore);
        let customer_balance = balance::value(&amount);
        let amount_value = coin::value
    /// Adds more points to the transaction escrow.
    public entry fun add_funds_to_escrow(transaction: &mut Transaction, amount: Coin<SUI>, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == transaction.customer, ENotStore);
        let amount_value = coin::value(&amount);

        // Check if the customer has enough SUI balance to cover the additional points
        let customer_balance = balance::value(&amount);
        assert!(customer_balance >= amount_value, EInsufficientFunds);

        balance::join(&mut transaction.escrow, amount);

        emit_event(TransactionEvent {
            id: object::new(ctx),
            transaction_id: transaction.id,
            action: b"Funds Added to Escrow".to_vec(),
            timestamp: clock::timestamp_ms(ctx),
        });
    }

    /// Updates the transaction details (item, price, quantity) before acceptance.
    public entry fun update_transaction_details(transaction: &mut Transaction, item: vector<u8>, quantity: u64, price: u64, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == transaction.customer, ENotStore);
        assert!(!is_some(&transaction.store), EInvalidTransaction);

        transaction.item = item;
        transaction.quantity = quantity;
        transaction.price = price;

        emit_event(TransactionEvent {
            id: object::new(ctx),
            transaction_id: transaction.id,
            action: b"Transaction Details Updated".to_vec(),
            timestamp: clock::timestamp_ms(ctx),
        });
    }

    /// Cancels the transaction if it hasn't been accepted by a store.
    public entry fun cancel_transaction(transaction: &mut Transaction, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == transaction.customer, ENotStore);
        assert!(!is_some(&transaction.store), EInvalidTransaction);

        let escrow_amount = balance::value(&transaction.escrow);
        if escrow_amount > 0 {
            let escrow_coin = coin::take(&mut transaction.escrow, escrow_amount, ctx);
            transfer::public_transfer(escrow_coin, transaction.customer);
        }

        emit_event(TransactionEvent {
            id: object::new(ctx),
            transaction_id: transaction.id,
            action: b"Transaction Cancelled".to_vec(),
            timestamp: clock::timestamp_ms(ctx),
        });
    }

    /// Updates the status of the transaction.
    public entry fun update_transaction_status(transaction: &mut Transaction, status: vector<u8>, ctx: &mut TxContext) {
        assert!(contains(&transaction.store, &tx_context::sender(ctx)), ENotStore);

        transaction.status = status;

        emit_event(TransactionEvent {
            id: object::new(ctx),
            transaction_id: transaction.id,
            action: b"Transaction Status Updated".to_vec(),
            timestamp: clock::timestamp_ms(ctx),
        });
    }

    // Add the necessary helper functions to emit events
    public fun emit_event(event: TransactionEvent) {
        event::emit(event);
    }
}
