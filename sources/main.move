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

// Error codes for various error conditions
const EInvalidTransaction: u64 = 1;
const EInvalidItem: u64 = 2;
const EDispute: u64 = 3;
const EAlreadyResolved: u64 = 4;
const ENotStore: u64 = 5;
const EInvalidWithdrawal: u64 = 6;
const EDeadlinePassed: u64 = 7;
const EInsufficientEscrow: u64 = 8;

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
}

/// Store accepts the transaction.
public entry fun accept_transaction(transaction: &mut Transaction, ctx: &mut TxContext) {
assert!(!is_some(&transaction.store), EInvalidTransaction);
transaction.store = some(tx_context::sender(ctx));
}

/// Fulfills the transaction.
public entry fun fulfill_transaction(transaction: &mut Transaction, clock: &Clock, ctx: &mut TxContext) {
assert!(contains(&transaction.store, &tx_context::sender(ctx)), EInvalidItem);
assert!(clock::timestamp_ms(clock) < transaction.deadline, EDeadlinePassed);
transaction.transactionFulfilled = true;
}

/// Marks the transaction as complete.
public entry fun mark_transaction_complete(transaction: &mut Transaction, ctx: &mut TxContext) {
assert!(contains(&transaction.store, &tx_context::sender(ctx)), ENotStore);
transaction.transactionFulfilled = true;
}

/// Raises a dispute for the transaction.
public entry fun dispute_transaction(transaction: &mut Transaction, ctx: &mut TxContext) {
assert!(transaction.customer == tx_context::sender(ctx), EDispute);
transaction.dispute = true;
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
