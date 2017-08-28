pragma solidity ^0.4.11;

import "./imported/openzeppelin/SafeMath.sol";
import "./MultisigLogic/MultisigLogic.sol";

contract ReservationFee {
  using SafeMath for uint256;

  address wallet;
  MultisigLogic multisigLogic;

  enum State { Initial, Reservation, Completed, Contribution, End }
  State public state;

  struct PaymentDetails {
    uint etherPaid;
    uint dgxContributed;
  }

  mapping (address => bool) public whitelist;
  mapping (address => PaymentDetails) public registrations;

  address public whitelister;
  address public fundraiser;
  uint public reservationStartTime;
  uint public minETHPayment;
  uint public multipleETHPayment;
  uint public maxETHPaymentTotal;
  uint public maxETHPaymentPerAcct;
  uint public dgxPerMinETHPayment;
  uint public totalEtherPaid;

  event Tx(string eventName, address indexed contributor, uint amount);
  event MultiSigOpsStatus(string status, bytes32 msg);

  /**
   * @dev Constuctor, setting up the contract.
   * @param _wallet the forwarding wallet address.
   * @param _logic the multisig logic.
   */
  function ReservationFee(address _wallet, address _logic) {
    wallet = _wallet;
    multisigLogic = MultisigLogic(_logic);

    reservationStartTime = 1501509600; // 07/31/2017 @ 2:00pm (UTC)
    /*
    minETHPayment = 5 * 1 ether;
    maxETHPaymentPerAcct = 250 * 1 ether;
    maxETHPaymentTotal = 4030 * 1 ether;
    */
    multipleETHPayment = minETHPayment;
    dgxPerMinETHPayment = 100 * 10**9;

    // for testing - start
    minETHPayment = 2 * 1 ether;
    maxETHPaymentPerAcct = 100 * 1 ether;
    maxETHPaymentTotal = 1612 * 1 ether;
    multipleETHPayment = minETHPayment;
    dgxPerMinETHPayment = 100 * 10**9;
    // for testing - end

    whitelister = msg.sender;
    fundraiser = msg.sender;

    // sets Initial state.
    state = State.Initial;
  }

  /**
   * @dev payable fallback function, called when contributor sends ETH (with or without value) to the contract.
   */
  function () external payable {
    require(msg.value>0);
    if (state==State.Initial && now >= reservationStartTime) {
      state = State.Reservation;
    }
    reserve(msg.sender, msg.value);
  }

  /**
   * @dev Entry point of `_amount` ETH paid from `_contributor`. It should meet the min ETH payment amount,
   * within reservation period, in reservation state.
   * @param _contributor address The address of contributor.
   * @param _amount uint The ETH payment amount.
   */
  function reserve(address _contributor, uint _amount) internal reservationState hasMinEtherPayment {
    require(!isContract(_contributor));
    require(isInWhitelist(_contributor));

    // accepts only in multiple of multipleETHPayment. refunds the rest.
    uint acceptedAmount = _amount.div(multipleETHPayment).mul(multipleETHPayment);
    uint refundAmount = _amount % multipleETHPayment;

    // accepts only as per cap per account, refunds the rest.
    uint remainingPaymentAllowedPerAcct = maxETHPaymentPerAcct.sub(registrations[_contributor].etherPaid);
    if (remainingPaymentAllowedPerAcct < acceptedAmount) {
      refundAmount = refundAmount.add(acceptedAmount.sub(remainingPaymentAllowedPerAcct));
      acceptedAmount = remainingPaymentAllowedPerAcct;
    }

    // accepts only as per cap in total, refunds the rest.
    uint remainingPaymentAllowedTotal = maxETHPaymentTotal.sub(totalEtherPaid);
    if (remainingPaymentAllowedTotal < acceptedAmount) {
      refundAmount = refundAmount.add(acceptedAmount.sub(remainingPaymentAllowedTotal));
      acceptedAmount = remainingPaymentAllowedTotal;
    }

    if (acceptedAmount > 0) {
      registrations[_contributor].etherPaid = registrations[_contributor].etherPaid.add(acceptedAmount);
      totalEtherPaid = totalEtherPaid.add(acceptedAmount);

      if (totalEtherPaid == maxETHPaymentTotal) {
        state = State.Completed;
      }
    }
    if (refundAmount > 0) {
      _contributor.transfer(refundAmount);
    }
    Tx("EtherPaid", _contributor, acceptedAmount);
    Tx("EtherRefunded", _contributor, refundAmount);
  }

  /**
   * @dev Determines if `_addr` is a contract address.
   * @param _addr address The address being queried.
   */
  function isContract(address _addr) constant internal returns (bool) {
    if (_addr == 0) return false;
    uint256 size;
    assembly {
      size := extcodesize(_addr)
    }
    return (size > 0);
  }

  /**
   * @dev Allows whitelister to add `_contributor` to the whitelist.
   * @param _contributor address The address of contributor.
   */
  function addToWhitelist(address _contributor) whitelisterOnly {
    whitelist[_contributor] = true;
  }

  /**
   * @dev Allows authorized signatories to remove `_contributor` from the whitelist.
   * @param _contributor address The address of contributor.
   */
  function removeFromWhitelist(address _contributor) internal {
    whitelist[_contributor] = false;
  }

  /**
   * @dev Checks if `_contributor` is in the whitelist.
   * @param _contributor address The address of contributor.
   */
  function isInWhitelist(address _contributor) constant returns (bool) {
    return (whitelist[_contributor] == true);
  }

  /**
   * @dev Marks DGX contribution for `_contributor` with amount `_amount`.
   * @param _contributor address The address of contributor.
   */
  function markDgxContribution(address _contributor, uint _amount) fundraiserOnly contributionState {
    require(isInWhitelist(_contributor));
    registrations[_contributor].dgxContributed = registrations[_contributor].dgxContributed.add(_amount);
    Tx("DGXContributed", _contributor, _amount);
  }

  /**
   * @dev Retrieves `_contributor` payment amount.
   * @param _contributor address The address of contributor.
   */
  function getPaymentAmount(address _contributor) constant returns (uint) {
    return registrations[_contributor].etherPaid;
  }

  /**
   * @dev Retrieves `_contributor` contribution amount of dgx.
   * @param _contributor address The address of contributor.
   */
  function getDgxContributionAmount(address _contributor) constant returns (uint) {
    return registrations[_contributor].dgxContributed;
  }

  /**
   * @dev Allows authorized callers to transfer all remaining Ether to MultisigWallet, after multisig approvals.
   * @param _h bytes32 the hash of multisig operation.
   */
  function sendAllEther(bytes32 _h) apo {
    bytes32 _hash;
    bool _status;
    (_hash, _status) = multisigLogic.executeOrConfirm(msg.sender, _h);
    if (_status) {
      MultiSigOpsStatus("Confirmed", _hash);
      wallet.transfer(this.balance);
    } else {
      MultiSigOpsStatus("ConfirmationNeeded", _hash);
    }
  }

  /**
   * @dev Allows authorized signatories to update contributor address.
   * @param _old address the old contributor address.
   * @param _new address the new contributor address.
   */
  function updateContributorAddress(address _old, address _new) apo {
    require(isContract(_new));
    removeFromWhitelist(_old);
    addToWhitelist(_new);
    registrations[_new].etherPaid = registrations[_old].etherPaid;
    registrations[_new].dgxContributed = registrations[_old].dgxContributed;
    registrations[_old].etherPaid = 0;
    registrations[_old].dgxContributed = 0;
  }

  /**
   * @dev Allows authorized signatories to update `_new` as new whitelister.
   * @param _new address The address of new whitelister.
   */
  function updateWhitelister(address _new) apo {
    whitelister = _new;
  }
  /**
   * @dev Allows authorized signatories to update `_new` as new fundraiser.
   * @param _new address The address of new fundraiser.
   */
  function updateFundraiser(address _new) apo {
    fundraiser = _new;
  }

  /// @dev activate state
  function setStateReservation() apo { state = State.Reservation; }
	function setStateCompleted() apo { state = State.Completed; }
  function setStateContribution() apo { state = State.Contribution; }
  function setStateEnd() apo { state = State.End; }

  /// @dev state modifiers
  modifier reservationState() { require(state == State.Reservation); _; }
  modifier completedState() { require(state == State.Completed); _; }
  modifier contributionState() { require(state == State.Contribution); _; }

  /**
   * @dev Modifier that throws if ETH sent does not meet the min ETH payment amount.
   */
  modifier hasMinEtherPayment {
    require(msg.value>=minETHPayment);
    _;
  }

  /**
   * @dev Modifier that throws if sender is not whitelister.
   */
  modifier whitelisterOnly {
    require(msg.sender == whitelister);
    _;
  }

  /**
   * @dev Modifier that throws if sender is not fundraiser.
   */
  modifier fundraiserOnly {
    require(msg.sender == fundraiser);
    _;
  }

  /**
   * @dev Modifier that throws if senders are not authorized.
   */
  modifier apo {
    require(multisigLogic.isOwner(msg.sender));
    _;
  }
}
