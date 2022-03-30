// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IFeeDistributor{
    function feeTokensLength() external view returns (uint256);
    function feeTokens(uint256 i) external view returns (address);
    function claimable(address _user, address[] calldata _tokens)
        external view returns (uint256[] memory amounts);
    function claim(address _user, address[] calldata _tokens)
        external returns (uint256[] memory claimedAmounts);
    function depositFee(address _token, uint256 _amount) external returns (bool);
}