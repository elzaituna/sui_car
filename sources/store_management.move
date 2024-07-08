module store_management::store_management {

    // Imports 
    use sui::transfer;
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::object::{Self, UID};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};
    use std::option::{Option, none, some, is_some, contains, borrow};
    use std::string::{String, utf8}; // New import for string operations

    // Error codes (added more for new functions)
    const EInvalidTransaction: u64 = 1;
    const EInvalidItem: u64 = 2;
    const EDispute: u64 = 3;
    const EAlreadyResolved: u64 = 4;
    const ENotStore: u64 = 5;
    const EInvalidWithdrawal: u64 = 6;
    const EDeadlinePassed: u64 = 7;
    const EInsufficientEscrow: u64 = 8;
    const EInvalidRating: u64 = 9;
    const ETransactionNotFulfilled: u64 = 10;

    // Struct definitions 
    struct Transaction has key, store {
        id: UID,
        customer: address,
        item: String,  // Changed from vector<u8> to String
        quantity: u64,
        price: u64,
        escrow: Balance<SUI>,
        dispute: bool,
        rating: Option<u64>,
        status: String,  // Changed from vector<u8> to String
        store: Option<address>,
        transactionFulfilled: bool,
        created_at: u64,
        deadline: u64,
    }

    struct ItemReview has key, store {
        id: UID,
        customer: address,
        review: String,  // Changed from vector<u8> to String
        rating: u64,  // Added rating field
    }

    // New struct for store statistics
    struct StoreStatistics has key, store {
        id: UID,
        store: address,
        total_transactions: u64,
        total_revenue: u64,
        average_rating: u64,
    }

    // Accessors (unchanged)
    public fun get_item(transaction: &Transaction): String {
        transaction.item
    }

    public fun get_transaction_price(transaction: &Transaction): u64 {
        transaction.price
    }

    public fun get_transaction_status(transaction: &Transaction): String {
        transaction.status
    }

    public fun get_transaction_deadline(transaction: &Transaction): u64 {
        transaction.deadline
    }

    // Public - Entry functions (improved and new functions added)

    public entry fun create_transaction(item: String, quantity: u64, price: u64, clock: &Clock, duration: u64, ctx: &mut TxContext) {
        let transaction_id = object::new(ctx);
        let deadline = clock::timestamp_ms(clock) + duration;
        transfer::share_object(Transaction {
            id: transaction_id,
            customer: tx_context::sender(ctx),
            store: none(),
            item,
            quantity,
            rating: none(),
            status: utf8(b"open"),
            price,
            escrow: balance::zero(),
            transactionFulfilled: false,
            dispute: false,
            created_at: clock::timestamp_ms(clock),
            deadline,
        });
    }

    public entry fun accept_transaction(transaction: &mut Transaction, ctx: &mut TxContext) {
        assert!(!is_some(&transaction.store), EInvalidTransaction);
        transaction.store = some(tx_context::sender(ctx));
        transaction.status = utf8(b"accepted");
    }

    public entry fun fulfill_transaction(transaction: &mut Transaction, clock: &Clock, ctx: &mut TxContext) {
        assert!(contains(&transaction.store, &tx_context::sender(ctx)), EInvalidItem);
        assert!(clock::timestamp_ms(clock) < transaction.deadline, EDeadlinePassed);
        transaction.transactionFulfilled = true;
        transaction.status = utf8(b"fulfilled");
    }

    public entry fun dispute_transaction(transaction: &mut Transaction, reason: String, ctx: &mut TxContext) {
        assert!(transaction.customer == tx_context::sender(ctx), EDispute);
        transaction.dispute = true;
        transaction.status = utf8(b"disputed");
    }

    public entry fun resolve_dispute(transaction: &mut Transaction, resolved: bool, ctx: &mut TxContext) {
        assert!(contains(&transaction.store, &tx_context::sender(ctx)), EDispute);
        assert!(transaction.dispute, EAlreadyResolved);
        
        let escrow_amount = balance::value(&transaction.escrow);
        let escrow_coin = coin::take(&mut transaction.escrow, escrow_amount, ctx);
        
        if (resolved) {
            let store = *borrow(&transaction.store);
            transfer::public_transfer(escrow_coin, store);
            transaction.status = utf8(b"resolved_for_store");
        } else {
            transfer::public_transfer(escrow_coin, transaction.customer);
            transaction.status = utf8(b"resolved_for_customer");
        };

        transaction.dispute = false;
    }

    public entry fun release_payment(transaction: &mut Transaction, clock: &Clock, review: String, rating: u64, ctx: &mut TxContext) {
        assert!(transaction.customer == tx_context::sender(ctx), ENotStore);
        assert!(transaction.transactionFulfilled && !transaction.dispute, EInvalidItem);
        assert!(clock::timestamp_ms(clock) > transaction.deadline, EDeadlinePassed);
        assert!(is_some(&transaction.store), EInvalidTransaction);
        assert!(rating >= 1 && rating <= 5, EInvalidRating);

        let store = *borrow(&transaction.store);
        let escrow_amount = balance::value(&transaction.escrow);
        assert!(escrow_amount > 0, EInsufficientEscrow);

        let escrow_coin = coin::take(&mut transaction.escrow, escrow_amount, ctx);
        transfer::public_transfer(escrow_coin, store);

        let itemReview = ItemReview {
            id: object::new(ctx),
            customer: tx_context::sender(ctx),
            review,
            rating,
        };

        transfer::public_transfer(itemReview, store);

        transaction.rating = some(rating);
        transaction.status = utf8(b"completed");

        // Update store statistics
        update_store_statistics(store, escrow_amount, rating, ctx);
    }

    // New function to update store statistics
    fun update_store_statistics(store: address, revenue: u64, rating: u64, ctx: &mut TxContext) {
        // This function assumes that StoreStatistics object already exists for the store
        // In a real implementation, you'd need to handle the case where it doesn't exist yet
        let stats = borrow_global_mut<StoreStatistics>(store);
        stats.total_transactions = stats.total_transactions + 1;
        stats.total_revenue = stats.total_revenue + revenue;
        stats.average_rating = (stats.average_rating * (stats.total_transactions - 1) + rating) / stats.total_transactions;
    }

    // New function to get store statistics
    public fun get_store_statistics(store: address): (u64, u64, u64) {
        let stats = borrow_global<StoreStatistics>(store);
        (stats.total_transactions, stats.total_revenue, stats.average_rating)
    }

    // New function to extend transaction deadline
    public entry fun extend_deadline(transaction: &mut Transaction, extension: u64, ctx: &mut TxContext) {
        assert!(contains(&transaction.store, &tx_context::sender(ctx)), ENotStore);
        transaction.deadline = transaction.deadline + extension;
    }

    // New function to partially refund customer
    public entry fun partial_refund(transaction: &mut Transaction, refund_amount: u64, ctx: &mut TxContext) {
        assert!(contains(&transaction.store, &tx_context::sender(ctx)), ENotStore);
        assert!(balance::value(&transaction.escrow) >= refund_amount, EInsufficientEscrow);

        let refund_coin = coin::take(&mut transaction.escrow, refund_amount, ctx);
        transfer::public_transfer(refund_coin, transaction.customer);
    }

    // New function to get transaction details
    public fun get_transaction_details(transaction: &Transaction): (address, String, u64, u64, String, bool, Option<u64>) {
        (
            transaction.customer,
            transaction.item,
            transaction.quantity,
            transaction.price,
            transaction.status,
            transaction.dispute,
            transaction.rating
        )
    }

    /// Marks the transaction as complete.
    public entry fun mark_transaction_complete(transaction: &mut Transaction, ctx: &mut TxContext) {
        assert!(contains(&transaction.store, &tx_context::sender(ctx)), ENotStore);
        transaction.transactionFulfilled = true;
    }

    // Reset transaction state
        transaction.store = none();
        transaction.transactionFulfilled = false;
        transaction.dispute = false;
    }

    /// Adds more points to the transaction escrow.
    public entry fun add_funds(transaction: &mut Transaction, amount: Coin<SUI>, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == transaction.customer, ENotStore);
        let added_balance = coin::into_balance(amount);
        balance::join(&mut transaction.escrow, added_balance);
    }

    /// Cancels the transaction.
    public entry fun cancel_transaction(transaction: &mut Transaction, ctx: &mut TxContext) {
        assert!(transaction.customer == tx_context::sender(ctx) || contains(&transaction.store, &tx_context::sender(ctx)), ENotStore);

        // Refund points to the customer if not yet paid
        if (is_some(&transaction.store) && !transaction.transactionFulfilled && !transaction.dispute) {
        let escrow_amount = balance::value(&transaction.escrow);
        let escrow_coin = coin::take(&mut transaction.escrow, escrow_amount, ctx);
        transfer::public_transfer(escrow_coin, transaction.customer);
        };

        // Reset transaction state
        transaction.store = none();
        transaction.transactionFulfilled = false;
        transaction.dispute = false;
        }

        /// Rates the store for the transaction.
        public entry fun rate_store(transaction: &mut Transaction, rating: u64, ctx: &mut TxContext) {
        assert!(transaction.customer == tx_context::sender(ctx), ENotStore);
        transaction.rating = some(rating);
    }

    /// Updates the item in the transaction.
    public entry fun update_item(transaction: &mut Transaction, new_item: vector<u8>, ctx: &mut TxContext) {
        assert!(transaction.customer == tx_context::sender(ctx), ENotStore);
        transaction.item = new_item;
    }

    /// Updates the price of the transaction.
    public entry fun update_transaction_price(transaction: &mut Transaction, new_price: u64, ctx: &mut TxContext) {
        assert!(transaction.customer == tx_context::sender(ctx), ENotStore);
        transaction.price = new_price;
    }

    /// Updates the quantity of the item in the transaction.
    public entry fun update_transaction_quantity(transaction: &mut Transaction, new_quantity: u64, ctx: &mut TxContext) {
        assert!(transaction.customer == tx_context::sender(ctx), ENotStore);
        transaction.quantity = new_quantity;
    }

    /// Updates the deadline for the transaction.
    public entry fun update_transaction_deadline(transaction: &mut Transaction, new_deadline: u64, ctx: &mut TxContext) {
        assert!(transaction.customer == tx_context::sender(ctx), ENotStore);
        transaction.deadline = new_deadline;
    }

    /// Updates the status of the transaction.
    public entry fun update_transaction_status(transaction: &mut Transaction, completed: vector<u8>, ctx: &mut TxContext) {
        assert!(transaction.customer == tx_context::sender(ctx), ENotStore);
        transaction.status = completed;
    }

    /// Adds more points to the transaction escrow.
    public entry fun add_funds_to_transaction(transaction: &mut Transaction, amount: Coin<SUI>, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == transaction.customer, ENotStore);
        let added_balance = coin::into_balance(amount);
        balance::join(&mut transaction.escrow, added_balance);
    }

    /// Requests a refund from the transaction escrow.
    public entry fun request_refund(transaction: &mut Transaction, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == transaction.customer, ENotStore);
        assert!(!transaction.transactionFulfilled && !transaction.dispute, EInvalidWithdrawal); // Ensure the transaction is not fulfilled and there's no ongoing dispute

        let escrow_amount = balance::value(&transaction.escrow);
        let escrow_coin = coin::take(&mut transaction.escrow, escrow_amount, ctx);
        // Refund points to the customer
        transfer::public_transfer(escrow_coin, transaction.customer);

        // Reset transaction state
        transaction.store = none();
        transaction.transactionFulfilled = false;
        transaction.dispute = false;
    }
}
