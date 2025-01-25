// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title Interface for the Uniswap V3 Automation Manager's Swap Router
interface ISwapRouterCommon {
    event SetAllowlistedRouters(address[] routers, bool[] statuses);
    error InvalidRouter();
    error NotAllowlistedRouter();

    /// @notice Set allowlisted routers
    /// @dev If `NonfungiblePositionManager` is an allowlisted router, this contract may approve arbitrary address to
    /// spend NFTs it has been approved of.
    /// @dev If an ERC20 token is allowlisted as a router, `transferFrom` may be called to drain tokens approved
    /// to this contract during `mintOptimal` or `increaseLiquidityOptimal`.
    /// @dev If a malicious router is allowlisted and called without slippage control, the caller may lose tokens in an
    /// external swap. The router can't, however, drain ERC20 or ERC721 tokens which have been approved by other users
    /// to this contract. Because this contract doesn't contain `transferFrom` with random `from` address like that in
    /// SushiSwap's [`RouteProcessor2`](https://rekt.news/sushi-yoink-rekt/).
    function setAllowlistedRouters(address[] calldata routers, bool[] calldata statuses) external payable;
}
