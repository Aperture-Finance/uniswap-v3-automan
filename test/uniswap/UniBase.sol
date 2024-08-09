// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {WETH as IWETH} from "solady/src/tokens/WETH.sol";
import "solady/src/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "@pancakeswap/v3-core/contracts/interfaces/callback/IPancakeV3SwapCallback.sol";
import "@pancakeswap/v3-core/contracts/interfaces/callback/IPancakeV3MintCallback.sol";
import {ICommonNonfungiblePositionManager as INPM, IUniswapV3NonfungiblePositionManager as IUniV3NPM} from "@aperture_finance/uni-v3-lib/src/interfaces/IUniswapV3NonfungiblePositionManager.sol";
import "@aperture_finance/uni-v3-lib/src/LiquidityAmounts.sol";
import "src/libraries/OptimalSwap.sol";
import "./Helper.sol";

// Partial interface for the SlipStream factory.
interface ISlipStreamCLFactory {
    /// @notice Returns the pool address for a given pair of tokens and a tick spacing, or address 0 if it does not exist
    /// @dev tokenA and tokenB may be passed in either token0/token1 or token1/token0 order
    /// @param tokenA The contract address of either token0 or token1
    /// @param tokenB The contract address of the other token
    /// @param tickSpacing The tick spacing of the pool
    /// @return pool The pool address
    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address pool);
}

/// @dev Base contract for Uniswap v3 tests
abstract contract UniBase is
    Test,
    Helper,
    IERC721Receiver,
    IERC1271,
    IUniswapV3SwapCallback,
    IUniswapV3MintCallback,
    IPancakeV3SwapCallback,
    IPancakeV3MintCallback
{
    using SafeTransferLib for address;
    using TickMath for int24;

    // The default DEX is 'UniV3' because that is the zero value of the enum.
    UniBase.DEX internal dex;
    INPM internal npm;

    uint256 internal chainId;
    address payable internal WETH;
    address internal USDC;
    address internal token0;
    address internal token1;
    uint24 internal constant fee = 500;
    int24 internal constant tickSpacingSlipStream = 100;

    address internal factory;
    address internal pool;
    uint8 internal token0Decimals;
    uint256 internal token0Unit;
    uint8 internal token1Decimals;
    uint256 internal token1Unit;
    int24 internal tickSpacing;

    bytes32 internal PERMIT_TYPEHASH;
    bytes32 internal DOMAIN_SEPARATOR;
    uint256 internal _nonce = 1;
    address internal user;
    uint256 internal pk;

    enum DEX {
        UniV3,
        PCSV3,
        SlipStream
    }

    // Configure state variables for each chain before creating a fork
    function initBeforeFork() internal returns (string memory chainAlias, uint256 blockNumber) {
        if (dex == DEX.UniV3) {
            chainAlias = "mainnet";
            blockNumber = 17000000;
            npm = INPM(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
            USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        } else if (dex == DEX.PCSV3) {
            chainAlias = "mainnet";
            blockNumber = 17000000;
            npm = INPM(0x46A15B0b27311cedF172AB29E4f4766fbE7F4364);
            USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        } else {
            // SlipStream
            chainAlias = "base";
            blockNumber = 17447600;
            npm = INPM(0x827922686190790b37229fd06084350E74485b72);
            USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        }
    }

    // Configure state variables for each chain after creating a fork
    function initAfterFork() internal {
        factory = npm.factory();
        WETH = payable(npm.WETH9());
        if (WETH < USDC) {
            token0 = WETH;
            token1 = USDC;
        } else {
            token0 = USDC;
            token1 = WETH;
        }
        if (dex == DEX.SlipStream) {
            pool = ISlipStreamCLFactory(factory).getPool(token0, token1, tickSpacingSlipStream);
        } else {
            pool = IUniswapV3Factory(factory).getPool(token0, token1, fee);
        }
        tickSpacing = V3PoolCallee.wrap(pool).tickSpacing();
        token0Decimals = IERC20Metadata(token0).decimals();
        token0Unit = 10 ** token0Decimals;
        token1Decimals = IERC20Metadata(token1).decimals();
        token1Unit = 10 ** token1Decimals;

        PERMIT_TYPEHASH = npm.PERMIT_TYPEHASH();
        DOMAIN_SEPARATOR = npm.DOMAIN_SEPARATOR();
        (user, pk) = makeAddrAndKey("user");
    }

    function setUp() public virtual {
        (string memory chainAlias, uint256 blockNumber) = initBeforeFork();
        vm.createSelectFork(chainAlias, blockNumber);
        initAfterFork();
        vm.label(WETH, "WETH");
        vm.label(USDC, "USDC");
        vm.label(address(npm), "NPM");
        vm.label(pool, "pool");
        vm.label(address(this), "UniTest");
    }

    /************************************************
     *  CRYPTOGRAPHY
     ***********************************************/

    /// @dev Returns the digest used in the permit signature verification
    function permitDigest(address spender, uint256 tokenId, uint256 deadline) internal view returns (bytes32) {
        (uint96 nonce, , , , , , , , , , , ) = IUniV3NPM(address(npm)).positions(tokenId);
        return
            MessageHashUtils.toTypedDataHash(
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, spender, tokenId, nonce, deadline))
            );
    }

    /// @dev Signs a permit digest with a private key
    function permitSig(
        address spender,
        uint256 tokenId,
        uint256 deadline,
        uint256 privateKey
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        return vm.sign(privateKey, permitDigest(spender, tokenId, deadline));
    }

    /// @dev Signs a permit digest using this contract
    function sign(bytes32 hash) public returns (uint8 v, bytes32 r, bytes32 s) {
        return vm.sign(_nonce++, hash);
    }

    /**
     * @dev Should return whether the signature provided is valid for the provided data
     * @param hash      Hash of the data to be signed
     * @param signature Signature byte array associated with _data
     */
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue) {
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly ("memory-safe") {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        if (vm.addr(_nonce - 1) == ecrecover(hash, v, r, s)) {
            return IERC1271.isValidSignature.selector;
        }
    }

    /************************************************
     *  HELPERS
     ***********************************************/

    function sqrtPriceX96() internal view returns (uint160 sqrtRatioX96) {
        (sqrtRatioX96, ) = V3PoolCallee.wrap(pool).sqrtPriceX96AndTick();
    }

    function currentTick() internal view returns (int24 tick) {
        (, tick) = V3PoolCallee.wrap(pool).sqrtPriceX96AndTick();
    }

    /// @dev Normalize tick to align with tick spacing
    function matchSpacing(int24 tick) internal view returns (int24) {
        int24 _tickSpacing = tickSpacing;
        return TickBitmap.compress(tick, _tickSpacing) * _tickSpacing;
    }

    /// @dev Get ERC20 or ETH balance
    function balanceOf(address token, address account) public view returns (uint256) {
        return token == WETH ? account.balance : IERC20(token).balanceOf(account);
    }

    /// @dev Normalize ticks to be valid
    function prepTicks(int24 tickLower, int24 tickUpper) internal view returns (int24, int24) {
        int24 MIN_TICK = matchSpacing(TickMath.MIN_TICK) + tickSpacing;
        int24 MAX_TICK = matchSpacing(TickMath.MAX_TICK);
        tickLower = matchSpacing(int24(bound(tickLower, MIN_TICK, MAX_TICK)));
        tickUpper = matchSpacing(int24(bound(tickUpper, MIN_TICK, MAX_TICK)));
        if (tickLower > tickUpper) (tickLower, tickUpper) = (tickUpper, tickLower);
        else if (tickLower == tickUpper) tickUpper += tickSpacing;
        return (tickLower, tickUpper);
    }

    /// @dev Normalize token amounts
    function prepAmounts(uint256 amount0Desired, uint256 amount1Desired) internal view returns (uint256, uint256) {
        address _pool = pool;
        uint256 balance0 = IERC20(token0).balanceOf(_pool);
        uint256 balance1 = IERC20(token1).balanceOf(_pool);
        amount0Desired = bound(amount0Desired, 0, balance0 / 10);
        amount1Desired = bound(amount1Desired, 0, balance1 / 10);
        if (amount0Desired < token0Unit / 1e3 && amount1Desired < token1Unit / 1e3) {
            amount0Desired = bound(uint256(keccak256(abi.encode(amount0Desired))), token0Unit / 1e3, balance0 / 10);
            amount1Desired = bound(uint256(keccak256(abi.encode(amount1Desired))), token1Unit / 1e3, balance1 / 10);
        }
        return (amount0Desired, amount1Desired);
    }

    /// @dev Prepare for optimal swap
    function prepOptimalSwap(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal returns (int24, int24, uint256, uint256, uint256, uint256, bool) {
        (tickLower, tickUpper) = prepTicks(tickLower, tickUpper);
        (amount0Desired, amount1Desired) = prepAmounts(amount0Desired, amount1Desired);
        console2.log("currentTick %d", int256(currentTick()));
        console2.log("tickUpper %d", int256(tickUpper));
        console2.log("tickLower %d", int256(tickLower));
        emit log_named_decimal_uint("amount0", amount0Desired, token0Decimals);
        emit log_named_decimal_uint("amount1", amount1Desired, token1Decimals);
        (uint256 amtSwap, uint256 amtOut, bool zeroForOne, ) = OptimalSwap.getOptimalSwap(
            V3PoolCallee.wrap(pool),
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired
        );
        console2.log("zeroForOne %s", zeroForOne);
        emit log_named_decimal_uint("amtSwap", amtSwap, ternary(zeroForOne, token0Decimals, token1Decimals));
        emit log_named_decimal_uint("amtOut", amtOut, ternary(zeroForOne, token1Decimals, token0Decimals));
        // Ensure `amtSwap` is less than amount to add
        assertLe(amtSwap, ternary(zeroForOne, amount0Desired, amount1Desired));
        return (tickLower, tickUpper, amount0Desired, amount1Desired, amtSwap, amtOut, zeroForOne);
    }

    /// @dev Check if liquidity is a valid uint128
    function prepLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal view returns (bool ok, uint128 liquidity) {
        uint256 _liquidity = getLiquidityForAmounts(
            sqrtPriceX96(),
            tickLower.getSqrtRatioAtTick(),
            tickUpper.getSqrtRatioAtTick(),
            amount0Desired,
            amount1Desired
        );
        if (_liquidity != 0 && _liquidity < 1 << 127) {
            ok = true;
            liquidity = uint128(_liquidity);
        }
    }

    /// @dev Prepare amounts to add liquidity
    function prepAmountsForLiquidity(
        uint128 initialLiquidity,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtRatioAX96 = tickLower.getSqrtRatioAtTick();
        uint160 sqrtRatioBX96 = tickUpper.getSqrtRatioAtTick();
        uint160 sqrtRatio = sqrtPriceX96();
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatio,
            sqrtRatioAX96,
            sqrtRatioBX96,
            uint128(bound(initialLiquidity, 1, V3PoolCallee.wrap(pool).liquidity() / 10))
        );
        uint256 liquidity = getLiquidityForAmounts(sqrtRatio, sqrtRatioAX96, sqrtRatioBX96, amount0, amount1);
        vm.assume(liquidity != 0);
    }

    /// @dev Prepare amount to swap
    function prepSwap(bool zeroForOne, uint256 amountSpecified) internal returns (uint256) {
        if (zeroForOne) {
            amountSpecified = bound(amountSpecified, 1, IERC20(token0).balanceOf(pool) / 10);
            deal(token0, address(this), amountSpecified);
        } else {
            amountSpecified = bound(amountSpecified, 1, IERC20(token1).balanceOf(pool) / 10);
            deal(token1, address(this), amountSpecified);
        }
        return amountSpecified;
    }

    /// @dev Ensure that the swap is successful
    function assertSwapSuccess(bool zeroForOne, uint256 amountOut) internal view {
        (address tokenIn, address tokenOut) = switchIf(zeroForOne, token1, token0);
        assertEq(IERC20(tokenIn).balanceOf(address(this)), 0, "amountIn not exhausted");
        assertEq(IERC20(tokenOut).balanceOf(address(this)), amountOut, "amountOut mismatch");
    }

    /// @dev  Ensure that there is little leftover after optimal deposit
    function assertLittleLeftover() internal view {
        uint256 balance0Left = IERC20(token0).balanceOf(address(this));
        uint256 balance1Left = IERC20(token1).balanceOf(address(this));
        assertLe(address(this).balance, 1e12, "too much eth leftover");
        assertLe(balance0Left, token0Unit / 1e3, "too much token0 leftover");
        assertLe(balance1Left, token1Unit / 1e3, "too much token1 leftover");
    }

    /// @dev Ensure that the balance of the contract matches the amount added
    function assertBalanceMatch(
        address recipient,
        uint256 balance0Before,
        uint256 balance1Before,
        uint256 amount0,
        uint256 amount1,
        bool involvesETH
    ) internal view {
        assertTrue(amount0 != 0 || amount1 != 0, "amount0 or amount1 must be non-zero");
        assertEq(
            involvesETH ? balanceOf(token0, recipient) : IERC20(token0).balanceOf(recipient),
            amount0 + balance0Before,
            "amount0 mismatch"
        );
        assertEq(
            involvesETH ? balanceOf(token1, recipient) : IERC20(token1).balanceOf(recipient),
            amount1 + balance1Before,
            "amount1 mismatch"
        );
    }

    function assertZeroBalance(address target) internal view {
        assertEq(target.balance, 0, "ETH balance");
        assertEq(IERC20(token0).balanceOf(target), 0, "token0 balance");
        assertEq(IERC20(token1).balanceOf(target), 0, "token1 balance");
    }

    /************************************************
     *  ACTIONS
     ***********************************************/

    receive() external payable {}

    /// @inheritdoc IERC721Receiver
    function onERC721Received(address, address, uint, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @dev Pay pool to finish swap
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        if (amount0Delta > 0) token0.safeTransfer(pool, uint256(amount0Delta));
        if (amount1Delta > 0) token1.safeTransfer(pool, uint256(amount1Delta));
    }

    /// @dev Pay pool to finish swap
    function pancakeV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        if (amount0Delta > 0) token0.safeTransfer(pool, uint256(amount0Delta));
        if (amount1Delta > 0) token1.safeTransfer(pool, uint256(amount1Delta));
    }

    /// @dev Pay pool to finish minting
    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata) external {
        if (amount0Owed > 0) token0.safeTransfer(pool, amount0Owed);
        if (amount1Owed > 0) token1.safeTransfer(pool, amount1Owed);
    }

    /// @dev Pay pool to finish minting
    function pancakeV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata) external {
        if (amount0Owed > 0) token0.safeTransfer(pool, amount0Owed);
        if (amount1Owed > 0) token1.safeTransfer(pool, amount1Owed);
    }

    /// @dev Handle WETH
    function handleWETH(uint256 amount0Desired, uint256 amount1Desired) internal returns (uint256 value) {
        value = token0 == WETH ? amount0Desired : (token1 == WETH ? amount1Desired : 0);
        if (value != 0) IWETH(WETH).withdraw(value);
    }

    /// @dev Make a direct pool swap
    function swap(address recipient, uint256 amtSwap, bool zeroForOne) internal {
        if (amtSwap != 0) {
            IUniswapV3Pool(pool).swap(
                recipient,
                zeroForOne,
                int256(amtSwap),
                zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                new bytes(0)
            );
        }
    }

    /// @dev Make a direct pool mint
    function mint(
        address recipient,
        uint256 amount0Desired,
        uint256 amount1Desired,
        int24 tickLower,
        int24 tickUpper
    ) internal returns (bool success) {
        (bool ok, uint128 liquidity) = prepLiquidity(tickLower, tickUpper, amount0Desired, amount1Desired);
        if (ok)
            try IUniswapV3Pool(pool).mint(recipient, tickLower, tickUpper, liquidity, new bytes(0)) returns (
                uint256,
                uint256
            ) {
                success = true;
            } catch Error(string memory reason) {
                // `mint` may fail if liquidity is too high or tick range is too narrow
                assertEq(reason, "LO", "only catch liquidity overflow");
            }
    }

    /// @dev Make a direct pool swap and mint liquidity
    function swapAndMint(
        address recipient,
        uint256 amtSwap,
        bool zeroForOne,
        int24 tickLower,
        int24 tickUpper
    ) internal returns (bool success) {
        // Swap
        swap(recipient, amtSwap, zeroForOne);
        // Amounts remaining after swap
        uint256 amount0 = IERC20(token0).balanceOf(address(this));
        uint256 amount1 = IERC20(token1).balanceOf(address(this));
        success = mint(recipient, amount0, amount1, tickLower, tickUpper);
    }
}
