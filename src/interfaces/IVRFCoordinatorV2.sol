pragma solidity ^0.8.20;

interface IVRFCoordinatorV2 {

    function requestRandomWords(
        bytes32 keyHash,
        uint64 subId,
        uint16 minimumRequestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords
    ) external returns (uint256 requestId);

    function createSubscription() external returns (uint64 subId);

    function getSubscription(uint64 subId)
        external
        view
        returns (uint96 balance, uint64 reqCount, address owner, address[] memory consumers);

    function requestSubscriptionOwnerTransfer(uint64 subId, address newOwner) external;

    function acceptSubscriptionOwnerTransfer(uint64 subId) external;

    function addConsumer(uint64 subId, address consumer) external;

    function removeConsumer(uint64 subId, address consumer) external;

    function cancelSubscription(uint64 subId, address to) external;

    function pendingRequestExists(uint64 subId) external view returns (bool);
}
