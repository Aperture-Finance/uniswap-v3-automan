// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "./uniswap/UniHandler.sol";
import "src/PCSV3Automan.sol";
import "src/UniV3Automan.sol";
import "src/SlipStreamAutoman.sol";

/// @dev Test contract for UniV3Automan
contract UniV3AutomanTest is UniHandler {
    using SafeTransferLib for address;
    using TickMath for int24;

    address internal collector = makeAddr("collector");
    UniHandler internal handler;
    uint256 internal thisTokenId;
    uint256 internal userTokenId;

    uint24 internal newFee = 3000;

    function setUp() public virtual override {
        super.setUp();
        automan = new UniV3Automan(npm, address(this));
        setUpCommon();
    }

    function setUpCommon() internal {
        vm.label(address(automan), "Automan");
        handler = new UniHandler();
        vm.label(address(handler), "UniHandler");
        handler.init(automan, dex);

        // Set up automan
        automan.setFeeConfig(IAutomanCommon.FeeConfig({feeLimitPips: 5e16, feeCollector: collector}));
        address[] memory controllers = new address[](2);
        controllers[0] = address(this);
        controllers[1] = address(handler);
        bool[] memory statuses = new bool[](2);
        statuses[0] = true;
        statuses[1] = true;
        automan.setControllers(controllers, statuses);

        // Set up invariant test targets
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = UniHandler.mint.selector;
        selectors[1] = UniHandler.mintOptimal.selector;
        selectors[2] = UniHandler.increaseLiquidity.selector;
        selectors[3] = UniHandler.increaseLiquidityOptimal.selector;
        selectors[4] = UniHandler.decreaseLiquidity.selector;
        selectors[5] = UniHandler.decreaseLiquiditySingle.selector;
        selectors[6] = UniHandler.removeLiquidity.selector;
        selectors[7] = UniHandler.removeLiquiditySingle.selector;
        selectors[8] = UniHandler.reinvest.selector;
        selectors[9] = UniHandler.rebalance.selector;
        selectors[10] = UniHandler.swapBackAndForth.selector;
        targetSelector(FuzzSelector(address(handler), selectors));

        // Pre-mint LP positions
        (, , int24 tickLower, int24 tickUpper) = fixedInputs();
        thisTokenId = preMint(address(this), tickLower, tickUpper);
        userTokenId = preMint(user, tickLower, tickUpper);
        deal(address(this), 0);
    }

    /************************************************
     *  HELPERS
     ***********************************************/

    /// @dev Provide fixed inputs for gas comparison purpose
    function fixedInputs()
        internal
        view
        returns (uint256 amount0Desired, uint256 amount1Desired, int24 tickLower, int24 tickUpper)
    {
        int24 multiplier = 100;
        int24 tick = matchSpacing(currentTick());
        tickLower = tick - multiplier * tickSpacing;
        tickUpper = tick + multiplier * tickSpacing;
        amount0Desired = 10 ether;
        amount1Desired = 0;
        (amount0Desired, amount1Desired) = prepAmounts(amount0Desired, amount1Desired);
    }

    /// @dev Mint a v3 LP position
    function preMint(address recipient, int24 tickLower, int24 tickUpper) internal returns (uint256 tokenId) {
        (uint256 amount0, uint256 amount1) = prepAmountsForLiquidity(
            V3PoolCallee.wrap(pool).liquidity() / 10000,
            tickLower,
            tickUpper
        );
        tokenId = _mint(recipient, tickLower, tickUpper, amount0, amount1, false);
        console2.log("tokenId %d", tokenId);
    }

    /// @dev Verify tokenId of the last minted LP position
    function verifyTokenId(uint256 tokenId) internal view returns (bool success) {
        uint256 nlpBalance = npm.balanceOf(address(this));
        if (nlpBalance > 1) {
            assertEq(tokenId, npm.tokenOfOwnerByIndex(address(this), nlpBalance - 1), "tokenId must match");
            success = true;
        }
    }

    /************************************************
     *  ACCESS CONTROL TESTS
     ***********************************************/

    /// @dev Should revert if attempting to set NPM as router
    function testRevert_WhitelistNPMAsRouter() public {
        address[] memory routers = new address[](1);
        routers[0] = address(npm);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.expectRevert(IAutomanCommon.InvalidSwapRouter.selector);
        automan.setSwapRouters(routers, statuses);
    }

    /// @dev Should revert if attempting to set an ERC20 token as router
    function testRevert_WhitelistERC20AsRouter() public {
        address[] memory routers = new address[](1);
        routers[0] = address(WETH);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.expectRevert(IAutomanCommon.InvalidSwapRouter.selector);
        automan.setSwapRouters(routers, statuses);
        routers[0] = address(USDC);
        vm.expectRevert(IAutomanCommon.InvalidSwapRouter.selector);
        automan.setSwapRouters(routers, statuses);
    }

    /// @dev Should revert if the router is not whitelisted
    function testRevert_NotWhitelistedRouter() public {
        (uint256 amount0Desired, uint256 amount1Desired, int24 tickLower, int24 tickUpper) = fixedInputs();
        deal(amount0Desired, amount1Desired);
        token0.safeApprove(address(automan), type(uint256).max);
        token1.safeApprove(address(automan), type(uint256).max);
        vm.expectRevert(IAutomanCommon.NotWhitelistedRouter.selector);
        if (dex == DEX.SlipStream) {
            IAutomanSlipStreamMintRebalance(address(automan)).mintOptimal(
                ISlipStreamNPM.MintParams({
                    token0: token0,
                    token1: token1,
                    tickSpacing: tickSpacingSlipStream,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    amount0Desired: amount0Desired,
                    amount1Desired: amount1Desired,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: block.timestamp,
                    sqrtPriceX96: 0
                }),
                abi.encodePacked(npm)
            );
        } else {
            IAutomanUniV3MintRebalance(address(automan)).mintOptimal(
                IUniV3NPM.MintParams({
                    token0: token0,
                    token1: token1,
                    fee: fee,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    amount0Desired: amount0Desired,
                    amount1Desired: amount1Desired,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: block.timestamp
                }),
                abi.encodePacked(npm)
            );
        }
    }

    /// @dev Should revert if the caller is not the owner or controller
    function testRevert_NotAuthorizedForToken() public {
        uint256 tokenId = thisTokenId;
        (, , int24 tickLower, int24 tickUpper) = fixedInputs();
        npm.approve(address(automan), tokenId);
        // `user` is not the owner or controller.
        assertTrue(!automan.isController(user));
        vm.startPrank(user);
        vm.expectRevert(IAutomanCommon.NotApproved.selector);
        _decreaseLiquidity(tokenId, 1, 0);
        vm.expectRevert(IAutomanCommon.NotApproved.selector);
        _decreaseLiquiditySingle(tokenId, 1, true, 0);
        vm.expectRevert(IAutomanCommon.NotApproved.selector);
        _removeLiquidity(tokenId, 0);
        vm.expectRevert(IAutomanCommon.NotApproved.selector);
        _removeLiquiditySingle(tokenId, true, 0);
        vm.expectRevert(IAutomanCommon.NotApproved.selector);
        _reinvest(tokenId, 1e12);
        (tickLower, tickUpper) = prepTicks(0, 100);
        vm.expectRevert(IAutomanCommon.NotApproved.selector);
        _rebalance(tokenId, tickLower, tickUpper, 1e12);
    }

    /// @dev Should revert if the fee is greater than the limit
    function testRevert_FeeLimitExceeded() public {
        vm.expectRevert(IAutomanCommon.FeeLimitExceeded.selector);
        _decreaseLiquidity(thisTokenId, 1, 1e17);
    }

    /// @dev Decreasing liquidity without prior approval should fail
    function testRevert_NotApproved() public virtual {
        vm.expectRevert("Not approved");
        _decreaseLiquidity(thisTokenId, 1, 0);
    }

    /************************************************
     *  LIQUIDITY MANAGEMENT TESTS
     ***********************************************/

    function invariantZeroBalance() public view {
        assertZeroBalance(address(automan));
    }

    function assertBalance() internal view {
        assertZeroBalance(address(automan));
        assertLittleLeftover();
    }

    /// @dev Test minting a v3 LP position using optimal swap with fixed inputs for gas comparison purpose
    function test_Mint() public {
        (uint256 amount0Desired, uint256 amount1Desired, int24 tickLower, int24 tickUpper) = fixedInputs();
        testFuzz_Mint(amount0Desired, amount1Desired, tickLower, tickUpper, false);
    }

    /// @dev Test minting with wrong token order
    function testRevert_WrongTokenOrder_Mint() public {
        (, , int24 tickLower, int24 tickUpper) = fixedInputs();
        (uint256 amount0, uint256 amount1) = prepAmountsForLiquidity(
            V3PoolCallee.wrap(pool).liquidity() / 10000,
            tickLower,
            tickUpper
        );
        deal(amount0, amount1);
        token0.safeApprove(address(automan), type(uint256).max);
        token1.safeApprove(address(automan), type(uint256).max);
        vm.expectRevert();
        if (dex == DEX.SlipStream) {
            IAutomanSlipStreamMintRebalance(address(automan)).mint(
                ISlipStreamNPM.MintParams({
                    token0: token1,
                    token1: token0,
                    tickSpacing: tickSpacingSlipStream,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    amount0Desired: amount1,
                    amount1Desired: amount0,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: block.timestamp,
                    sqrtPriceX96: 0
                })
            );
        } else {
            IAutomanUniV3MintRebalance(address(automan)).mint(
                IUniV3NPM.MintParams({
                    token0: token1,
                    token1: token0,
                    fee: fee,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    amount0Desired: amount1,
                    amount1Desired: amount0,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: block.timestamp
                })
            );
        }
    }

    /// @dev Test minting a v3 LP position using optimal swap with fuzzed inputs
    function testFuzz_Mint(
        uint256 amount0Desired,
        uint256 amount1Desired,
        int24 tickLower,
        int24 tickUpper,
        bool sendValue
    ) public {
        uint256 amtSwap;
        bool zeroForOne;
        (tickLower, tickUpper, amount0Desired, amount1Desired, amtSwap, , zeroForOne) = prepOptimalSwap(
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired
        );
        deal(amount0Desired, amount1Desired);
        swap(address(this), amtSwap, zeroForOne);
        uint256 tokenId = _mint(
            address(this),
            tickLower,
            tickUpper,
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            sendValue
        );
        if (verifyTokenId(tokenId)) assertBalance();
    }

    /// @dev Test minting with built-in optimal swap
    function test_MintOptimal() public {
        (uint256 amount0Desired, uint256 amount1Desired, int24 tickLower, int24 tickUpper) = fixedInputs();
        (uint256 tokenId, ) = _mintOptimal(
            address(this),
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired,
            new bytes(0)
        );
        if (verifyTokenId(tokenId)) assertBalance();
    }

    /// @dev Should revert when minting with built-in optimal swap and wrong token order
    function testRevert_WrongTokenOrder_MintOptimal() public {
        (uint256 amount0Desired, uint256 amount1Desired, int24 tickLower, int24 tickUpper) = fixedInputs();
        deal(amount0Desired, amount1Desired);
        token0.safeApprove(address(automan), type(uint256).max);
        token1.safeApprove(address(automan), type(uint256).max);
        vm.expectRevert(OptimalSwap.Invalid_Pool.selector);
        if (dex == DEX.SlipStream) {
            IAutomanSlipStreamMintRebalance(address(automan)).mintOptimal(
                ISlipStreamNPM.MintParams({
                    token0: token1,
                    token1: token0,
                    tickSpacing: tickSpacingSlipStream,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    amount0Desired: amount1Desired,
                    amount1Desired: amount0Desired,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: block.timestamp,
                    sqrtPriceX96: 0
                }),
                new bytes(0)
            );
        } else {
            IAutomanUniV3MintRebalance(address(automan)).mintOptimal(
                IUniV3NPM.MintParams({
                    token0: token1,
                    token1: token0,
                    fee: fee,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    amount0Desired: amount1Desired,
                    amount1Desired: amount0Desired,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: block.timestamp
                }),
                new bytes(0)
            );
        }
    }

    /// @dev Test increasing liquidity of a v3 LP position using optimal swap with fixed inputs for gas comparison purpose
    function test_IncreaseLiquidity() public {
        uint256 amount0Desired;
        uint256 amount1Desired = 100000 * token1Unit;
        testFuzz_IncreaseLiquidity(amount0Desired, amount1Desired, false);
    }

    /// @dev Test increasing liquidity of a v3 LP position using optimal swap with fuzzed inputs
    function testFuzz_IncreaseLiquidity(uint256 amount0Desired, uint256 amount1Desired, bool sendValue) public {
        (, , int24 tickLower, int24 tickUpper) = fixedInputs();
        uint256 amtSwap;
        bool zeroForOne;
        (tickLower, tickUpper, amount0Desired, amount1Desired, amtSwap, , zeroForOne) = prepOptimalSwap(
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired
        );
        deal(amount0Desired, amount1Desired);
        // Swap to the optimal ratio
        swap(address(this), amtSwap, zeroForOne);
        // Call automan to increase liquidity
        uint128 liquidity = _increaseLiquidity(
            thisTokenId,
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            sendValue
        );
        if (liquidity != 0) assertBalance();
    }

    /// @dev Test minting with built-in optimal swap
    function test_IncreaseLiquidityOptimal() public {
        (uint256 amount0Desired, uint256 amount1Desired, , ) = fixedInputs();
        uint128 liquidity = _increaseLiquidityOptimal(thisTokenId, amount0Desired, amount1Desired);
        if (liquidity != 0) assertBalance();
    }

    /// @dev Test decreasing liquidity of a v3 LP position
    function testFuzz_DecreaseLiquidity(uint128 liquidityDesired) public {
        uint256 tokenId = thisTokenId;
        (, , , , , , , uint128 liquidity, , , , ) = IUniV3NPM(address(npm)).positions(tokenId);
        liquidityDesired = uint128(bound(liquidityDesired, 1, liquidity));
        uint256 balance0Before = balanceOf(token0, address(this));
        uint256 balance1Before = balanceOf(token1, address(this));
        // Approve automan to decrease liquidity
        npm.setApprovalForAll(address(automan), true);
        (uint256 amount0, uint256 amount1) = _decreaseLiquidity(tokenId, liquidityDesired, 0);
        assertBalanceMatch(address(this), balance0Before, balance1Before, amount0, amount1, true);
    }

    /// @dev Should revert when withdrawn amounts are less than fees
    function testRevert_TooMuchFee() public {
        uint256 tokenId = thisTokenId;
        npm.approve(address(automan), tokenId);
        vm.expectRevert(IAutomanCommon.InsufficientAmount.selector);
        _decreaseLiquidity(tokenId, 10, 1e16);
    }

    /// @dev Decreasing liquidity with permit
    function testFuzz_DecreaseLiquidity_WithPermit(uint128 liquidityDesired) public {
        uint256 tokenId = userTokenId;
        (, , , , , , , uint128 liquidity, , , , ) = IUniV3NPM(address(npm)).positions(tokenId);
        liquidityDesired = uint128(bound(liquidityDesired, 1, liquidity));
        uint256 deadline = block.timestamp;
        (uint8 v, bytes32 r, bytes32 s) = permitSig(address(automan), tokenId, deadline, pk);
        automan.decreaseLiquidity(
            INPM.DecreaseLiquidityParams(tokenId, liquidityDesired, 0, 0, deadline),
            0,
            deadline,
            v,
            r,
            s
        );
    }

    /// @dev Test decreasing liquidity of a v3 LP position and withdrawing a single token
    function testFuzz_DecreaseLiquiditySingle(uint128 liquidityDesired, bool zeroForOne) public {
        uint256 tokenId = thisTokenId;
        (, , , , , , , uint128 liquidity, , , , ) = IUniV3NPM(address(npm)).positions(tokenId);
        liquidityDesired = uint128(bound(liquidityDesired, 1, liquidity));
        uint256 balanceBefore = zeroForOne ? balanceOf(token1, address(this)) : balanceOf(token0, address(this));
        // Approve automan to decrease liquidity
        npm.approve(address(automan), tokenId);
        uint256 amount = _decreaseLiquiditySingle(tokenId, liquidityDesired, zeroForOne, 0);
        assertEq(
            zeroForOne ? balanceOf(token1, address(this)) : balanceOf(token0, address(this)),
            balanceBefore + amount,
            "amount mismatch"
        );
    }

    /// @dev Decreasing liquidity with permit
    function testFuzz_DecreaseLiquiditySingle_WithPermit(uint128 liquidityDesired, bool zeroForOne) public {
        uint256 tokenId = thisTokenId;
        (, , , , , , , uint128 liquidity, , , , ) = IUniV3NPM(address(npm)).positions(tokenId);
        liquidityDesired = uint128(bound(liquidityDesired, 1, liquidity));
        uint256 deadline = block.timestamp;
        (uint8 v, bytes32 r, bytes32 s) = sign(permitDigest(address(automan), tokenId, deadline));
        automan.decreaseLiquiditySingle(
            INPM.DecreaseLiquidityParams(tokenId, liquidityDesired, 0, 0, deadline),
            zeroForOne,
            0,
            new bytes(0),
            deadline,
            v,
            r,
            s
        );
    }

    /// @dev Test removing liquidity from a v3 LP position
    function test_RemoveLiquidity() public {
        uint256 tokenId = thisTokenId;
        uint256 balance0Before = balanceOf(token0, address(this));
        uint256 balance1Before = balanceOf(token1, address(this));
        // Approve automan to remove liquidity
        npm.approve(address(automan), tokenId);
        uint256 gasBefore = gasleft();
        (uint256 amount0, uint256 amount1) = _removeLiquidity(tokenId, 1e16);
        console2.log("gas used", gasBefore - gasleft());
        assertBalanceMatch(address(this), balance0Before, balance1Before, amount0, amount1, true);
        assertGt(balanceOf(token0, collector), 0, "!fee");
        assertGt(balanceOf(token1, collector), 0, "!fee");
    }

    /// @dev Test removing liquidity from a v3 LP position with permit
    function test_RemoveLiquidity_WithPermit() public {
        uint256 tokenId = userTokenId;
        uint256 balance0Before = balanceOf(token0, user);
        uint256 balance1Before = balanceOf(token1, user);
        uint256 deadline = block.timestamp;
        (uint8 v, bytes32 r, bytes32 s) = permitSig(address(automan), tokenId, deadline, pk);
        uint256 gasBefore = gasleft();
        (uint256 amount0, uint256 amount1) = automan.removeLiquidity(
            INPM.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: 0,
                amount0Min: 0,
                amount1Min: 0,
                deadline: deadline
            }),
            0,
            deadline,
            v,
            r,
            s
        );
        console2.log("gas used", gasBefore - gasleft());
        assertBalanceMatch(user, balance0Before, balance1Before, amount0, amount1, true);
    }

    /// @dev Test removing liquidity from a v3 LP position and withdrawing a single token
    function testFuzz_RemoveLiquiditySingle(bool zeroForOne) public {
        uint256 tokenId = thisTokenId;
        uint256 balanceBefore = zeroForOne ? balanceOf(token1, address(this)) : balanceOf(token0, address(this));
        // Approve automan to remove liquidity
        npm.approve(address(automan), tokenId);
        uint256 amount = _removeLiquiditySingle(tokenId, zeroForOne, 1e16);
        assertEq(
            zeroForOne ? balanceOf(token1, address(this)) : balanceOf(token0, address(this)),
            balanceBefore + amount,
            "amount mismatch"
        );
        assertGt(zeroForOne ? balanceOf(token1, collector) : balanceOf(token0, collector), 0, "!fee");
    }

    /// @dev Test removing liquidity from a v3 LP position and withdrawing a single token with permit
    function testFuzz_RemoveLiquiditySingle_WithPermit(bool zeroForOne) public {
        uint256 tokenId = thisTokenId;
        uint256 deadline = block.timestamp;
        (uint8 v, bytes32 r, bytes32 s) = sign(permitDigest(address(automan), tokenId, deadline));
        automan.removeLiquiditySingle(
            INPM.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: 0,
                amount0Min: 0,
                amount1Min: 0,
                deadline: deadline
            }),
            zeroForOne,
            0,
            new bytes(0),
            deadline,
            v,
            r,
            s
        );
    }

    /// @dev Test reinvesting a v3 LP position
    function test_Reinvest() public {
        uint256 tokenId = userTokenId;
        swapBackAndForth(100000 * token0Unit, true);
        vm.prank(user);
        npm.approve(address(automan), tokenId);
        uint256 gasBefore = gasleft();
        uint128 liquidity = _reinvest(tokenId, 1e12);
        console2.log("gas used", gasBefore - gasleft());
        assertGt(liquidity, 0, "liquidity must increase");
        assertGt(balanceOf(token0, collector), 0, "!fee");
        assertGt(balanceOf(token1, collector), 0, "!fee");
        invariantZeroBalance();
    }

    /// @dev Test reinvesting a v3 LP position
    function testFuzz_Reinvest(uint256 amountIn, bool zeroForOne) public {
        uint256 tokenId = userTokenId;
        swapBackAndForth(amountIn, zeroForOne);
        vm.prank(user);
        npm.approve(address(automan), tokenId);
        uint128 liquidity = _reinvest(tokenId, 1e9);
        assertGt(liquidity, 0, "liquidity must increase");
        assertTrue(balanceOf(token0, collector) > 0 || balanceOf(token1, collector) > 0, "!fee");
        invariantZeroBalance();
    }

    /// @dev Test reinvesting a v3 LP position with permit
    function testFuzz_Reinvest_WithPermit(uint256 amountIn, bool zeroForOne) public {
        uint256 tokenId = userTokenId;
        swapBackAndForth(amountIn, zeroForOne);
        uint256 deadline = block.timestamp;
        (uint8 v, bytes32 r, bytes32 s) = permitSig(address(automan), tokenId, deadline, pk);
        _reinvest(tokenId, 1e9, deadline, v, r, s);
    }

    /// @dev Test rebalancing a v3 LP position
    function testFuzz_Rebalance(int24 tickLower, int24 tickUpper) public {
        if (dex == DEX.SlipStream) {
            tickSpacing = 100;
        } else {
            tickSpacing = V3PoolCallee.wrap(IUniswapV3Factory(factory).getPool(token0, token1, newFee)).tickSpacing();
        }
        (tickLower, tickUpper) = prepTicks(tickLower, tickUpper);
        npm.setApprovalForAll(address(automan), true);
        if (dex == DEX.SlipStream) {
            try
                IAutomanSlipStreamMintRebalance(address(automan)).rebalance(
                    ISlipStreamNPM.MintParams({
                        token0: token0,
                        token1: token1,
                        tickSpacing: tickSpacingSlipStream,
                        tickLower: tickLower,
                        tickUpper: tickUpper,
                        amount0Desired: 0,
                        amount1Desired: 0,
                        amount0Min: 0,
                        amount1Min: 0,
                        recipient: address(0),
                        deadline: block.timestamp,
                        sqrtPriceX96: 0
                    }),
                    thisTokenId,
                    1e12,
                    new bytes(0)
                )
            returns (uint256 newTokenId, uint128 liquidity, uint256, uint256) {
                assertEq(npm.ownerOf(newTokenId), address(this), "owner mismatch");
                assertGt(liquidity, 0, "liquidity cannot be zero");
                assertGt(balanceOf(token0, collector), 0, "!fee");
                assertGt(balanceOf(token1, collector), 0, "!fee");
                invariantZeroBalance();
            } catch Error(string memory reason) {
                assertEq(reason, "LO", "only catch liquidity overflow");
            }
        } else {
            try
                IAutomanUniV3MintRebalance(address(automan)).rebalance(
                    IUniV3NPM.MintParams({
                        token0: token0,
                        token1: token1,
                        fee: newFee,
                        tickLower: tickLower,
                        tickUpper: tickUpper,
                        amount0Desired: 0,
                        amount1Desired: 0,
                        amount0Min: 0,
                        amount1Min: 0,
                        recipient: address(0),
                        deadline: block.timestamp
                    }),
                    thisTokenId,
                    1e12,
                    new bytes(0)
                )
            returns (uint256 newTokenId, uint128 liquidity, uint256, uint256) {
                assertEq(npm.ownerOf(newTokenId), address(this), "owner mismatch");
                assertGt(liquidity, 0, "liquidity cannot be zero");
                assertGt(balanceOf(token0, collector), 0, "!fee");
                assertGt(balanceOf(token1, collector), 0, "!fee");
                invariantZeroBalance();
            } catch Error(string memory reason) {
                assertEq(reason, "LO", "only catch liquidity overflow");
            }
        }
    }

    /// @dev Test rebalancing a v3 LP position with permit
    function testFuzz_Rebalance_WithPermit(int24 tickLower, int24 tickUpper) public {
        uint256 tokenId = userTokenId;
        uint256 deadline = block.timestamp;
        (uint8 v, bytes32 r, bytes32 s) = permitSig(address(automan), tokenId, deadline, pk);
        if (dex == DEX.SlipStream) {
            tickSpacing = 100;
        } else {
            tickSpacing = V3PoolCallee.wrap(IUniswapV3Factory(factory).getPool(token0, token1, newFee)).tickSpacing();
        }
        (tickLower, tickUpper) = prepTicks(tickLower, tickUpper);
        if (dex == DEX.SlipStream) {
            try
                IAutomanSlipStreamMintRebalance(address(automan)).rebalance(
                    ISlipStreamNPM.MintParams({
                        token0: token0,
                        token1: token1,
                        tickSpacing: tickSpacingSlipStream,
                        tickLower: tickLower,
                        tickUpper: tickUpper,
                        amount0Desired: 0,
                        amount1Desired: 0,
                        amount0Min: 0,
                        amount1Min: 0,
                        recipient: address(0),
                        deadline: deadline,
                        sqrtPriceX96: 0
                    }),
                    tokenId,
                    1e12,
                    new bytes(0),
                    deadline,
                    v,
                    r,
                    s
                )
            {} catch Error(string memory reason) {
                assertEq(reason, "LO", "only catch liquidity overflow");
            }
        } else {
            try
                IAutomanUniV3MintRebalance(address(automan)).rebalance(
                    IUniV3NPM.MintParams({
                        token0: token0,
                        token1: token1,
                        fee: newFee,
                        tickLower: tickLower,
                        tickUpper: tickUpper,
                        amount0Desired: 0,
                        amount1Desired: 0,
                        amount0Min: 0,
                        amount1Min: 0,
                        recipient: address(0),
                        deadline: deadline
                    }),
                    tokenId,
                    1e12,
                    new bytes(0),
                    deadline,
                    v,
                    r,
                    s
                )
            {} catch Error(string memory reason) {
                assertEq(reason, "LO", "only catch liquidity overflow");
            }
        }
    }
}

contract PCSV3AutomanTest is UniV3AutomanTest {
    function setUp() public override {
        newFee = 500;
        dex = DEX.PCSV3;
        UniBase.setUp();
        automan = new PCSV3Automan(IPCSV3NonfungiblePositionManager(address(npm)), address(this));
        setUpCommon();
    }
}

contract SlipStreamAutomanTest is UniV3AutomanTest {
    function setUp() public override {
        dex = DEX.SlipStream;
        UniBase.setUp();
        automan = new SlipStreamAutoman(npm, address(this));
        setUpCommon();
    }

    /// @dev Decreasing liquidity without prior approval should fail.
    /// @dev SlipStream does not revert with "Not approved" but with no data.
    function testRevert_NotApproved() public override {
        vm.expectRevert(bytes(""));
        _decreaseLiquidity(thisTokenId, 1, 0);
    }
}
