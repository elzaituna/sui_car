# Store Management System

This project implements a decentralized store management system on the Sui blockchain. It facilitates transactions between customers and stores, enabling customers to purchase items using points, raise disputes, and leave reviews. The system ensures that points are held in escrow until the transaction is successfully completed or resolved.

## Features

- **Create Transaction:** Customers can initiate transactions to purchase items from the store.
- **Accept Transaction:** Stores can accept transactions initiated by customers.
- **Fulfill Transaction:** Stores can fulfill accepted transactions.
- **Complete Transaction:** Mark a transaction as complete once fulfilled.
- **Dispute Transaction:** Customers can raise disputes if there are issues with the transaction.
- **Resolve Dispute:** Resolve disputes between customers and stores, releasing escrowed points accordingly.
- **Release Payment:** Release payment to the store after a transaction is successfully fulfilled.
- **Add Funds:** Add more points to the transaction escrow.
- **Cancel Transaction:** Cancel transactions and refund points if conditions are met.
- **Rate Store:** Customers can rate the store for a completed transaction.
- **Update Transaction:** Update transaction details like item, price, quantity, deadline, and status.
- **Request Refund:** Customers can request refunds for unfulfilled transactions.

## Struct Definitions

### Transaction
Represents a transaction in the store.
- `id`: Unique identifier for the transaction.
- `customer`: Address of the customer.
- `item`: Item being transacted.
- `quantity`: Quantity of the item.
- `price`: Price of the item in points.
- `escrow`: Escrow balance for the transaction.
- `dispute`: Dispute status.
- `rating`: Rating given by the customer.
- `status`: Status of the transaction.
- `store`: Address of the store (initially None, set when accepted).
- `transactionFulfilled`: Whether the transaction is fulfilled.
- `created_at`: Timestamp when the transaction was created.
- `deadline`: Deadline for the transaction.

### ItemReview
Represents a review for an item.
- `id`: Unique identifier for the review.
- `customer`: Address of the customer who reviewed.
- `review`: Review text.

## Error Codes

- `EInvalidTransaction`: Invalid transaction operation.
- `EInvalidItem`: Invalid item operation.
- `EDispute`: Dispute raised on the transaction.
- `EAlreadyResolved`: Dispute already resolved.
- `ENotStore`: Unauthorized store operation.
- `EInvalidWithdrawal`: Invalid withdrawal request.
- `EDeadlinePassed`: Transaction deadline passed.
- `EInsufficientEscrow`: Insufficient points in escrow.

## Accessor Functions

- `get_item(transaction: &Transaction): vector<u8>`
- `get_transaction_price(transaction: &Transaction): u64`
- `get_transaction_status(transaction: &Transaction): vector<u8>`
- `get_transaction_deadline(transaction: &Transaction): u64`

## Entry Functions

- `create_transaction(item: vector<u8>, quantity: u64, price: u64, clock: &Clock, duration: u64, open: vector<u8>, ctx: &mut TxContext)`
- `accept_transaction(transaction: &mut Transaction, ctx: &mut TxContext)`
- `fulfill_transaction(transaction: &mut Transaction, clock: &Clock, ctx: &mut TxContext)`
- `mark_transaction_complete(transaction: &mut Transaction, ctx: &mut TxContext)`
- `dispute_transaction(transaction: &mut Transaction, ctx: &mut TxContext)`
- `resolve_dispute(transaction: &mut Transaction, resolved: bool, ctx: &mut TxContext)`
- `release_payment(transaction: &mut Transaction, clock: &Clock, review: vector<u8>, ctx: &mut TxContext)`
- `add_funds(transaction: &mut Transaction, amount: Coin<SUI>, ctx: &mut TxContext)`
- `cancel_transaction(transaction: &mut Transaction, ctx: &mut TxContext)`
- `rate_store(transaction: &mut Transaction, rating: u64, ctx: &mut TxContext)`
- `update_item(transaction: &mut Transaction, new_item: vector<u8>, ctx: &mut TxContext)`
- `update_transaction_price(transaction: &mut Transaction, new_price: u64, ctx: &mut TxContext)`
- `update_transaction_quantity(transaction: &mut Transaction, new_quantity: u64, ctx: &mut TxContext)`
- `update_transaction_deadline(transaction: &mut Transaction, new_deadline: u64, ctx: &mut TxContext)`
- `update_transaction_status(transaction: &mut Transaction, completed: vector<u8>, ctx: &mut TxContext)`
- `add_funds_to_transaction(transaction: &mut Transaction, amount: Coin<SUI>, ctx: &mut TxContext)`
- `request_refund(transaction: &mut Transaction, ctx: &mut TxContext)`

## Usage

To use this module, follow these steps:

1. **Create a Transaction:** Call the `create_transaction` function to initiate a transaction.
2. **Store Accepts Transaction:** The store can accept the transaction by calling `accept_transaction`.
3. **Fulfill and Complete Transaction:** The store fulfills the transaction, and it can be marked as complete.
4. **Dispute and Resolve:** If there are issues, customers can raise disputes which can then be resolved.
5. **Release Payment:** Once fulfilled, payment can be released to the store.
6. **Manage Escrow:** Points can be added to the escrow, and transactions can be canceled or refunded if necessary.
7. **Rate and Review:** Customers can rate the store and leave reviews for items.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
```
