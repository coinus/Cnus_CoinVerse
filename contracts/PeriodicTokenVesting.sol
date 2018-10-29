pragma solidity 0.4.24;

import "openzeppelin-solidity/contracts/token/ERC20/TokenVesting.sol";


/** @title Periodic Token Vesting
  * @dev A token holder contract that can release its token balance periodically like a
  * typical vesting scheme. Optionally revocable by the owner.
  */
contract PeriodicTokenVesting is TokenVesting {
    using SafeMath for uint256;

    uint256 public releasePeriod;
    uint256 public releaseCount;

    mapping (address => uint256) public revokedAmount;

    constructor(
        address _beneficiary,
        uint256 _startInUnixEpochTime,
        uint256 _releasePeriodInSeconds,
        uint256 _releaseCount
    )
        public
        TokenVesting(_beneficiary, _startInUnixEpochTime, 0, _releasePeriodInSeconds.mul(_releaseCount), true)
    {
        releasePeriod = _releasePeriodInSeconds;
        releaseCount = _releaseCount;
    }

    function initialTokenAmountInVesting(ERC20Basic _token) public view returns (uint256) {
        return _token.balanceOf(address(this)).add(released[_token]).add(revokedAmount[_token]);
    }

    function tokenAmountLockedInVesting(ERC20Basic _token) public view returns (uint256) {
        return _token.balanceOf(address(this)).sub(releasableAmount(_token));
    }

    function nextVestingTime(ERC20Basic _token) public view returns (uint256) {
        if (block.timestamp >= start.add(duration) || revoked[_token]) {
            return 0;
        } else {
            return start.add(((block.timestamp.sub(start)).div(releasePeriod).add(1)).mul(releasePeriod));
        }
    }

    function vestingCompletionTime(ERC20Basic _token) public view returns (uint256) {
        if (block.timestamp >= start.add(duration) || revoked[_token]) {
            return 0;
        } else {
            return start.add(duration);
        }
    }

    function remainingVestingCount(ERC20Basic _token) public view returns (uint256) {
        if (block.timestamp >= start.add(duration) || revoked[_token]) {
            return 0;
        } else {
            return releaseCount.sub((block.timestamp.sub(start)).div(releasePeriod));
        }
    }

    /**
     * @notice Allows the owner to revoke the vesting. Tokens already vested
     * remain in the contract, the rest are returned to the owner.
     * @param _token ERC20 token which is being vested
     */
    function revoke(ERC20Basic _token) public onlyOwner {
      require(revocable);
      require(!revoked[_token]);

      uint256 balance = _token.balanceOf(address(this));

      uint256 unreleased = releasableAmount(_token);
      uint256 refund = balance.sub(unreleased);

      revoked[_token] = true;
      revokedAmount[_token] = refund;

      _token.safeTransfer(owner, refund);

      emit Revoked();
    }

    /**
     * @dev Calculates the amount that has already vested.
     * @param _token ERC20 token which is being vested
     */
    function vestedAmount(ERC20Basic _token) public view returns (uint256) {
        uint256 currentBalance = _token.balanceOf(address(this));
        uint256 totalBalance = currentBalance.add(released[_token]);

        if (block.timestamp < cliff) {
            return 0;
        } else if (block.timestamp >= start.add(duration) || revoked[_token]) {
            return totalBalance;
        } else {
            return totalBalance.mul((block.timestamp.sub(start)).div(releasePeriod)).div(releaseCount);
        }
    }
}
