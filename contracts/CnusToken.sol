pragma solidity 0.4.24;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/BurnableToken.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/StandardToken.sol";
import "./PeriodicTokenVesting.sol";


/** @title Cnus Token
  * An ERC20-compliant token.
  */
contract CnusToken is StandardToken, Ownable, BurnableToken {
    using SafeMath for uint256;

    // global token transfer lock
    bool public globalTokenTransferLock = false;
    bool public mintingFinished = false;
    bool public lockingDisabled = false;

    string public name = "CoinUs";
    string public symbol = "CNUS";
    uint256 public decimals = 18;

    address public mintContractOwner;

    address[] public vestedAddresses;

    // mapping that provides address based lock.
    mapping( address => bool ) public lockedStatusAddress;
    mapping( address => PeriodicTokenVesting ) private tokenVestingContracts;

    event LockingDisabled();
    event GlobalLocked();
    event GlobalUnlocked();
    event Locked(address indexed lockedAddress);
    event Unlocked(address indexed unlockedaddress);
    event Mint(address indexed to, uint256 amount);
    event MintFinished();
    event MintOwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event VestingCreated(address indexed beneficiary, uint256 startTime, uint256 period, uint256 releaseCount);
    event InitialVestingDeposited(address indexed beneficiary, uint256 amount);
    event AllVestedTokenReleased();
    event VestedTokenReleased(address indexed beneficiary);
    event RevokedTokenVesting(address indexed beneficiary);

    // Check for global lock status to be unlocked
    modifier checkGlobalTokenTransferLock {
        if (!lockingDisabled) {
            require(!globalTokenTransferLock, "Global lock is active");
        }
        _;
    }

    // Check for address lock to be unlocked
    modifier checkAddressLock {
        require(!lockedStatusAddress[msg.sender], "Address is locked");
        _;
    }

    modifier canMint() {
        require(!mintingFinished, "Minting is finished");
        _;
    }

    modifier hasMintPermission() {
        require(msg.sender == mintContractOwner, "Minting is not authorized from this account");
        _;
    }

    constructor() public {
        uint256 initialSupply = 2000000000;
        initialSupply = initialSupply.mul(10**18);
        totalSupply_ = initialSupply;
        balances[msg.sender] = initialSupply;
        mintContractOwner = msg.sender;
    }

    function disableLockingForever() public
    onlyOwner
    {
        lockingDisabled = true;
        emit LockingDisabled();
    }

    function setGlobalTokenTransferLock(bool locked) public
    onlyOwner
    {
        require(!lockingDisabled);
        require(globalTokenTransferLock != locked);
        globalTokenTransferLock = locked;
        if (globalTokenTransferLock) {
            emit GlobalLocked();
        } else {
            emit GlobalUnlocked();
        }
    }

    /**
      * @dev Allows token issuer to lock token transfer for an address.
      * @param target Target address to lock token transfer.
      */
    function lockAddress(
        address target
    )
        public
        onlyOwner
    {
        require(!lockingDisabled);
        require(owner != target);
        require(!lockedStatusAddress[target]);
        for(uint256 i = 0; i < vestedAddresses.length; i++) {
            require(tokenVestingContracts[vestedAddresses[i]] != target);
        }
        lockedStatusAddress[target] = true;
        emit Locked(target);
    }

    /**
      * @dev Allows token issuer to unlock token transfer for an address.
      * @param target Target address to unlock token transfer.
      */
    function unlockAddress(
        address target
    )
        public
        onlyOwner
    {
        require(!lockingDisabled);
        require(lockedStatusAddress[target]);
        lockedStatusAddress[target] = false;
        emit Unlocked(target);
    }

    /**
     * @dev Creates a vesting contract that vests its balance of Cnus token to the
     * _beneficiary, gradually in periodic interval until all of the balance will have
     * vested by period * release count time.
     * @param _beneficiary address of the beneficiary to whom vested tokens are transferred
     * @param _startInUnixEpochTime the time (as Unix time) at which point vesting starts
     * @param _releasePeriodInSeconds period in seconds in which tokens will vest to beneficiary
     * @param _releaseCount count of period required to have all of the balance vested
     */
    function createNewVesting(
        address _beneficiary,
        uint256 _startInUnixEpochTime,
        uint256 _releasePeriodInSeconds,
        uint256 _releaseCount
    )
        public
        onlyOwner
    {
        require(tokenVestingContracts[_beneficiary] == address(0));
        tokenVestingContracts[_beneficiary] = new PeriodicTokenVesting(
            _beneficiary, _startInUnixEpochTime, _releasePeriodInSeconds, _releaseCount);
        vestedAddresses.push(_beneficiary);
        emit VestingCreated(_beneficiary, _startInUnixEpochTime, _releasePeriodInSeconds, _releaseCount);
    }

    /**
      * @dev Transfers token vesting amount from token issuer to vesting contract created for the
      * beneficiary. Token Issuer must first approve token spending from owner's account.
      * @param _beneficiary beneficiary for whom vesting has been created with createNewVesting function.
      * @param _vestAmount vesting amount for the beneficiary
      */
    function transferInitialVestAmountFromOwner(
        address _beneficiary,
        uint256 _vestAmount
    )
        public
        onlyOwner
        returns (bool)
    {
        require(tokenVestingContracts[_beneficiary] != address(0));
        ERC20 cnusToken = ERC20(address(this));
        require(cnusToken.allowance(owner, address(this)) >= _vestAmount);
        require(cnusToken.transferFrom(owner, tokenVestingContracts[_beneficiary], _vestAmount));
        emit InitialVestingDeposited(_beneficiary, cnusToken.balanceOf(tokenVestingContracts[_beneficiary]));
        return true;
    }

    function checkVestedAddressCount()
        public
        view
        returns (uint256)
    {
        return vestedAddresses.length;
    }

    function checkCurrentTotolVestedAmount()
        public
        view
        returns (uint256)
    {
        uint256 vestedAmountSum = 0;
        for (uint256 i = 0; i < vestedAddresses.length; i++) {
            vestedAmountSum = vestedAmountSum.add(
                tokenVestingContracts[vestedAddresses[i]].vestedAmount(ERC20(address(this))));
        }
        return vestedAmountSum;
    }

    function checkCurrentTotalReleasableAmount()
        public
        view
        returns (uint256)
    {
        uint256 releasableAmountSum = 0;
        for (uint256 i = 0; i < vestedAddresses.length; i++) {
            releasableAmountSum = releasableAmountSum.add(
                tokenVestingContracts[vestedAddresses[i]].releasableAmount(ERC20(address(this))));
        }
        return releasableAmountSum;
    }

    function checkCurrentTotalAmountLockedInVesting()
        public
        view
        returns (uint256)
    {
        uint256 lockedAmountSum = 0;
        for (uint256 i = 0; i < vestedAddresses.length; i++) {
            lockedAmountSum = lockedAmountSum.add(
               tokenVestingContracts[vestedAddresses[i]].tokenAmountLockedInVesting(ERC20(address(this))));
        }
        return lockedAmountSum;
    }

    function checkInitialTotalTokenAmountInVesting()
        public
        view
        returns (uint256)
    {
        uint256 initialTokenVesting = 0;
        for (uint256 i = 0; i < vestedAddresses.length; i++) {
            initialTokenVesting = initialTokenVesting.add(
                tokenVestingContracts[vestedAddresses[i]].initialTokenAmountInVesting(ERC20(address(this))));
        }
        return initialTokenVesting;
    }

    function checkNextVestingTimeForBeneficiary(
        address _beneficiary
    )
        public
        view
        returns (uint256)
    {
        require(tokenVestingContracts[_beneficiary] != address(0));
        return tokenVestingContracts[_beneficiary].nextVestingTime(ERC20(address(this)));
    }

    function checkVestingCompletionTimeForBeneficiary(
        address _beneficiary
    )
        public
        view
        returns (uint256)
    {
        require(tokenVestingContracts[_beneficiary] != address(0));
        return tokenVestingContracts[_beneficiary].vestingCompletionTime(ERC20(address(this)));
    }

    function checkRemainingVestingCountForBeneficiary(
        address _beneficiary
    )
        public
        view
        returns (uint256)
    {
        require(tokenVestingContracts[_beneficiary] != address(0));
        return tokenVestingContracts[_beneficiary].remainingVestingCount(ERC20(address(this)));
    }

    function checkReleasableAmountForBeneficiary(
        address _beneficiary
    )
        public
        view
        returns (uint256)
    {
        require(tokenVestingContracts[_beneficiary] != address(0));
        return tokenVestingContracts[_beneficiary].releasableAmount(ERC20(address(this)));
    }

    function checkVestedAmountForBeneficiary(
        address _beneficiary
    )
        public
        view
        returns (uint256)
    {
        require(tokenVestingContracts[_beneficiary] != address(0));
        return tokenVestingContracts[_beneficiary].vestedAmount(ERC20(address(this)));
    }

    function checkTokenAmountLockedInVestingForBeneficiary(
        address _beneficiary
    )
        public
        view
        returns (uint256)
    {
        require(tokenVestingContracts[_beneficiary] != address(0));
        return tokenVestingContracts[_beneficiary].tokenAmountLockedInVesting(ERC20(address(this)));
    }

    /**
     * @notice Transfers vested tokens to all beneficiaries.
     */
    function releaseAllVestedToken()
        public
        checkGlobalTokenTransferLock
        returns (bool)
    {
        emit AllVestedTokenReleased();
        PeriodicTokenVesting tokenVesting;
        for(uint256 i = 0; i < vestedAddresses.length; i++) {
            tokenVesting = tokenVestingContracts[vestedAddresses[i]];
            if(tokenVesting.releasableAmount(ERC20(address(this))) > 0) {
                tokenVesting.release(ERC20(address(this)));
                emit VestedTokenReleased(vestedAddresses[i]);
            }
        }
        return true;
    }

    /**
     * @notice Transfers vested tokens to beneficiary.
     * @param _beneficiary Beneficiary to whom cnus token is being vested
     */
    function releaseVestedToken(
        address _beneficiary
    )
        public
        checkGlobalTokenTransferLock
        returns (bool)
    {
        require(tokenVestingContracts[_beneficiary] != address(0));
        tokenVestingContracts[_beneficiary].release(ERC20(address(this)));
        emit VestedTokenReleased(_beneficiary);
        return true;
    }

    /**
     * @notice Allows the owner to revoke the vesting. Tokens already vested
     * remain in the contract, the rest are returned to the owner.
     * @param _beneficiary Beneficiary to whom cnus token is being vested
     */
    function revokeTokenVesting(
        address _beneficiary
    )
        public
        onlyOwner
        checkGlobalTokenTransferLock
        returns (bool)
    {
        require(tokenVestingContracts[_beneficiary] != address(0));
        tokenVestingContracts[_beneficiary].revoke(ERC20(address(this)));
        _transferMisplacedToken(owner, address(this), ERC20(address(this)).balanceOf(address(this)));
        emit RevokedTokenVesting(_beneficiary);
        return true;
    }

    /** @dev Transfer `_value` token to `_to` from `msg.sender`, on the condition
      * that global token lock and individual address lock in the `msg.sender`
      * accountare both released.
      * @param _to The address of the recipient.
      * @param _value The amount of token to be transferred.
      * @return Whether the transfer was successful or not.
      */
    function transfer(
        address _to,
        uint256 _value
    )
        public
        checkGlobalTokenTransferLock
        checkAddressLock
        returns (bool)
    {
        return super.transfer(_to, _value);
    }

    /**
     * @dev Transfer tokens from one address to another
     * @param _from address The address which you want to send tokens from
     * @param _to address The address which you want to transfer to
     * @param _value uint256 the amount of tokens to be transferred
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    )
        public
        checkGlobalTokenTransferLock
        returns (bool)
    {
        require(!lockedStatusAddress[_from], "Address is locked.");
        return super.transferFrom(_from, _to, _value);
    }

    /**
     * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
     * @param _spender address The address which will spend the funds.
     * @param _value uint256 The amount of tokens to be spent.
     */
    function approve(
        address _spender,
        uint256 _value
    )
        public
        checkGlobalTokenTransferLock
        checkAddressLock
        returns (bool)
    {
        return super.approve(_spender, _value);
    }

    /**
     * @dev Increase the amount of tokens that an owner allowed to a spender.
     * approve should be called when allowed[_spender] == 0. To increment
     * allowed value is better to use this function to avoid 2 calls (and wait until
     * the first transaction is mined)
     * From MonolithDAO Token.sol
     * @param _spender The address which will spend the funds.
     * @param _addedValue The amount of tokens to increase the allowance by.
     */
    function increaseApproval(
        address _spender,
        uint _addedValue
    )
        public
        checkGlobalTokenTransferLock
        checkAddressLock
        returns (bool success)
    {
        return super.increaseApproval(_spender, _addedValue);
    }

    /**
     * @dev Decrease the amount of tokens that an owner allowed to a spender.
     * approve should be called when allowed[_spender] == 0. To decrement
     * allowed value is better to use this function to avoid 2 calls (and wait until
     * the first transaction is mined)
     * From MonolithDAO Token.sol
     * @param _spender The address which will spend the funds.
     * @param _subtractedValue The amount of tokens to decrease the allowance by.
     */
    function decreaseApproval(
        address _spender,
        uint _subtractedValue
    )
        public
        checkGlobalTokenTransferLock
        checkAddressLock
        returns (bool success)
    {
        return super.decreaseApproval(_spender, _subtractedValue);
    }

    /**
     * @dev Function to transfer mint ownership.
     * @param _newOwner The address that will have the mint ownership.
     */
    function transferMintOwnership(
        address _newOwner
    )
        public
        onlyOwner
    {
        _transferMintOwnership(_newOwner);
    }

    /**
     * @dev Function to mint tokens
     * @param _to The address that will receive the minted tokens.
     * @param _amount The amount of tokens to mint.
     * @return A boolean that indicates if the operation was successful.
     */
    function mint(
        address _to,
        uint256 _amount
    )
        public
        hasMintPermission
        canMint
        returns (bool)
    {
        totalSupply_ = totalSupply_.add(_amount);
        balances[_to] = balances[_to].add(_amount);
        emit Mint(_to, _amount);
        emit Transfer(address(0), _to, _amount);
        return true;
    }

    /**
     * @dev Function to stop minting new tokens.
     * @return True if the operation was successful.
     */
    function finishMinting()
        public
        onlyOwner
        canMint
        returns (bool)
    {
        mintingFinished = true;
        emit MintFinished();
        return true;
    }

    function checkMisplacedTokenBalance(
        address _tokenAddress
    )
        public
        view
        returns (uint256)
    {
        ERC20 unknownToken = ERC20(_tokenAddress);
        return unknownToken.balanceOf(address(this));
    }

    // Allow transfer of accidentally sent ERC20 tokens
    function refundMisplacedToken(
        address _recipient,
        address _tokenAddress,
        uint256 _value
    )
        public
        onlyOwner
    {
        _transferMisplacedToken(_recipient, _tokenAddress, _value);
    }

    function _transferMintOwnership(
        address _newOwner
    )
        internal
    {
        require(_newOwner != address(0));
        emit MintOwnershipTransferred(mintContractOwner, _newOwner);
        mintContractOwner = _newOwner;
    }

    function _transferMisplacedToken(
        address _recipient,
        address _tokenAddress,
        uint256 _value
    )
        internal
    {
        require(_recipient != address(0));
        ERC20 unknownToken = ERC20(_tokenAddress);
        require(unknownToken.balanceOf(address(this)) >= _value, "Insufficient token balance.");
        require(unknownToken.transfer(_recipient, _value));
    }
}
