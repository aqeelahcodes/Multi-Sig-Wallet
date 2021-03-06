// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

contract MultiSigWallet {
    
    /*
     *  Events
     */
     
    event Deposit(address indexed sender, uint amount, uint balance);
    event SubmitTransaction(address indexed owner, uint indexed txIndex, address indexed to, uint value, bytes data);
    event ConfirmTransaction(address indexed owner, uint indexed txIndex);
    event RevokeConfirmation(address indexed owner, uint indexed txIndex);
    event ExecuteTransaction(address indexed owner, uint indexed txIndex);
    event OwnerAddition(address indexed owner);
    event RequirementChange(uint required);
    
     /*
     *  Storage
     */
     
    address[] public owners;                                                                
    mapping(address => bool) public isOwner;  
    uint public numConfirmationsRequired;
    
    // transaction index => owner => bool
    mapping(uint => mapping(address => bool)) public isConfirmed;
    Transaction[] public transactions;   
    
    struct Transaction {                                                                   
        address to;                                                                         
        uint value;                                                                         
        bytes data;                                                                        
        bool executed;                                                                      
        uint numConfirmations;                                                             
    }
    
     /*
     *  Modifiers
     */
     
    modifier onlyOwner() {
        require(isOwner[msg.sender], "not owner");
        _;
    }
    
    modifier onlyWallet() {
        require(msg.sender == address(this));
        _;
    }
    
    modifier ownerDoesNotExist(address owner) {
        require(!isOwner[owner]);
        _;
    }
    
    modifier ownerExist(address owner) {
        require(isOwner[owner]);
        _;
    }
    
    modifier notNull(address owner) {
        require(owner != address(0));
        _;
    }
    
    modifier validRequirment(uint ownerCount, uint _numConfirmationsRequired) {
        require(ownerCount > 0 
            && _numConfirmationsRequired > 0
            && _numConfirmationsRequired <= ownerCount);
        _;
    }

    modifier txExists(uint _txIndex) {
        require(_txIndex < transactions.length, "tx does not exist");
        _;
    }

    modifier notExecuted(uint _txIndex) {
        require(!transactions[_txIndex].executed, "tx already executed");
        _;
    }

    modifier notConfirmed(uint _txIndex) {
        require(!isConfirmed[_txIndex][msg.sender], "tx already confirmed");
        _;
    }
    
    modifier Confirmed(uint _txIndex) {
        require(isConfirmed[_txIndex][msg.sender], "tx already confirmed");
        _;
    }
    
    /*
     * Public functions
     */
    
    /* Contract constructor sets the intial owners and required number of confirmations
       _owners List of initial owners 
       _numConfirmationsRequired Number of required confirmations
    */
    
    constructor(address[] memory _owners, uint _numConfirmationsRequired) 
        validRequirment(_owners.length, _numConfirmationsRequired)
    {
        for(uint i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "invalid owner");
            require(!isOwner[_owners[i]], "owner not unique");
            isOwner[owner] = true;
            owners.push(owner);
        }
        numConfirmationsRequired = _numConfirmationsRequired;
    }
    
    // Fallback function allows to deposit ether
    
    receive() payable external {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }
    
    // Helper function to deposit into Remix
    
    function deposit() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }
    
    // Allows address that deployed the contract to add a new owner
    // newOwner Address of the new owner
    
    function addOwner(address newOwner)
        public 
        onlyWallet
        ownerDoesNotExist(newOwner)
        notNull(newOwner)
        validRequirment(owners.length + 1, numConfirmationsRequired)
    {
        isOwner[newOwner] = true;
        owners.push(newOwner);
        
        emit OwnerAddition(newOwner);
    }
    
    // Allows address that deployed the contract to change the number of required confirmations
    // numConfirmationsRequired Number of required confirmations
    
    function changeConfirmationsRequired(uint _numConfirmationsRequired)
        public 
        onlyWallet
        validRequirment(owners.length, _numConfirmationsRequired)
    {
        numConfirmationsRequired = _numConfirmationsRequired;
        
        emit RequirementChange(_numConfirmationsRequired);
    }
    
    // Allows owner to submit a transaction
    // _to Transaction target address
    // _value Transaction ether value 
    // _data Transaction data
    
    function submitTransaction(address _to, uint _value, bytes memory _data) 
        public 
        onlyOwner 
        notNull(_to)
    {
        uint txIndex = transactions.length;
        
        transactions.push(Transaction({
            to: _to,
            value: _value,
            data: _data,
            executed: false,
            numConfirmations: 0
        }));
        
        emit SubmitTransaction(msg.sender, txIndex, _to, _value, _data);
    }
    
    // Allows owner to confirm a transaction 
    // _txIndex Transaction ID
    
    function confirmTransaction(uint _txIndex) 
        public 
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
        notConfirmed (_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];
        isConfirmed[_txIndex][msg.sender] = true;
        transaction.numConfirmations += 1;
        
        emit ConfirmTransaction(msg.sender, _txIndex);
    }
    
    // Allows anyone to execute a confirmed transaction
    // _txIndex Transaction ID
    
    function executeTransaction(uint _txIndex) 
        public
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];
        require(transaction.numConfirmations >= numConfirmationsRequired, "cannot execute");
        transaction.executed = true;
        (bool success, ) = transaction.to.call{value: transaction.value}(transaction.data);
        require(success, "tx failed");

        emit ExecuteTransaction(msg.sender, _txIndex);
    }
    
    // Allows owner to revoke a confirmation
    // _txIndex Transaction ID
    
    function revokeConfirmation(uint _txIndex)
        public
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];
        require(isConfirmed[_txIndex][msg.sender], "tx not confirmed");
        transaction.numConfirmations -= 1;
        isConfirmed[_txIndex][msg.sender] = false;
        
        emit RevokeConfirmation(msg.sender, _txIndex);

    }
    
    // Returns list of owners
    
    function getOwners() public view returns (address[] memory) {
        return owners;
    } 
    
    // Returns array with owner addresses, which confirmed transaction
    
    function getConfirmations(uint transactionId)
        public
        view
        returns (address[] memory _confirmations)
    {
        address[] memory confirmationsTemp = new address[](owners.length);
        uint count = 0;
        uint i;
        for (i=0; i<owners.length; i++)
            if (isConfirmed[transactionId][owners[i]]) {
                confirmationsTemp[count] = owners[i];
                count += 1;
            }
        _confirmations = new address[](count);
        for (i=0; i<count; i++)
            _confirmations[i] = confirmationsTemp[i];
    }
    
    // Returns list of transaction IDs in defined range
    
    function getTransaction(uint _txIndex)
        public
        view
        returns (address to, uint value, bytes memory data, bool executed, uint numConfirmations)
    {
        Transaction storage transaction = transactions[_txIndex];

        return (
            transaction.to,
            transaction.value,
            transaction.data,
            transaction.executed,
            transaction.numConfirmations
        );
    }
    
}
