// SPDX-License-Identifier: MIT
// forge script DevPlayground --fork-url arbitrum_one -vvvv
pragma solidity ^0.8.18;

import "forge-std/Script.sol";

contract DevPlayground is Script {

    // struct NestedToml {
    struct NestedTest {
        address a;
        bytes b;
    }

    function fromHexChar(uint8 c) public pure returns (uint8) {
        if (bytes1(c) >= bytes1('0') && bytes1(c) <= bytes1('9')) {
            return c - uint8(bytes1('0'));
        }
        if (bytes1(c) >= bytes1('a') && bytes1(c) <= bytes1('f')) {
            return 10 + c - uint8(bytes1('a'));
        }
        if (bytes1(c) >= bytes1('A') && bytes1(c) <= bytes1('F')) {
            return 10 + c - uint8(bytes1('A'));
        }
        revert("fail");
    }

    function fromHex(string memory s) public pure returns (bytes memory) {
        bytes memory ss = bytes(s);
        require(ss.length%2 == 0); // length must be even
        bytes memory r = new bytes(ss.length/2);
        for (uint i=0; i<ss.length/2; ++i) {
            r[i] = bytes1(fromHexChar(uint8(ss[2*i])) * 16 +
                        fromHexChar(uint8(ss[2*i+1])));
        }
        return r;
    }

    function checkRouter(bytes calldata swapData) public view returns (address router) {
        /**
            `msg.data` is encoded as `abi.encodePacked(token0, token1, fee, tickLower, tickUpper, zeroForOne,
            approvalTarget, router, data)`
            | Arg            | Offset   |
            |----------------|----------|
            | token0         | [0, 20)  |
            | token1         | [20, 40) |
            | fee            | [40, 43) |
            | tickLower      | [43, 46) |
            | tickUpper      | [46, 49) |
            | zeroForOne     | [49, 50) |
            | approvalTarget | [50, 70) |
            | router         | [70, 90) |
            | data.offset    | [90, )   |
         */
        // 0x1fFd5d818187917E0043522C3bE583A393c2BbF7
        // address is 40 chars or 20 bytes or 160 bits
        // assembly {
        //     router := shr(96, calldataload(swapData.offset))
        // }
        // console2.log("router: %s", router);
        // address routerShifted1Byte;
        // assembly {
        //     routerShifted1Byte := shr(88, calldataload(swapData.offset))
        // }
        // console2.log("routerShifted1Byte: %s", routerShifted1Byte);
        // address routerShifted1ByteRight;
        // assembly {
        //     routerShifted1ByteRight := shr(104, calldataload(swapData.offset))
        // }
        // console2.log("routerShifted1ByteRight: %s", routerShifted1ByteRight);
        // // address token0;
        // // assembly {
        // //     token0 := shl(64, calldataload(swapData.offset))
        // // }
        // // console2.log("token0: %s", token0);
        // address swapDataStart;
        // assembly {
        //     swapDataStart := calldataload(swapData.offset)
        // }
        // console2.log("swapDataStart: %s", swapDataStart);
        // address testCalldatacopy = 0x1fFd5d818187917E0043522C3bE583A393c2BbF7;
        // assembly {
        //     testCalldatacopy := mload(add(swapData.offset,20))
        // }
        // console2.log("testCalldatacopy: %s", testCalldatacopy);
        // uint256 swapDataOffset = 123;
        // assembly {
        //     swapDataOffset := swapData.offset
        // }
        // console2.log("swapDataOffset: %s", swapDataOffset);
        // address swapDataStart2;
        // assembly {
        //     swapDataStart2 := shr(0, calldataload(swapData.offset))
        // }
        // console2.log("swapDataStart2: %s", swapDataStart2);
        // // https://ethereum.stackexchange.com/questions/143522/how-to-decode-encodepacked-data
        // address stackExchange;
        // assembly {
        //     stackExchange := mload(add(swapData.offset, 68))
        // }
        // console2.log("stackExchange: %s", stackExchange);

        // // NestedTest memory decodedData = abi.decode(swapData, (NestedTest));
        // // console2.log("decodedData.a: %s", decodedData.a);
        // // console2.log("decodedData.b: %s", decodedData.b);

        // // https://ethereum.stackexchange.com/questions/148421/how-to-decode-a-nested-encodepacked
        // address stackExchange32;
        // assembly {
        //     stackExchange32 := calldataload(add(swapData.offset, 32))
        // }
        // console2.log("stackExchange32: %s", stackExchange32);
        // address stackExchange64;
        // assembly {
        //     stackExchange64 := calldataload(add(swapData.offset, 64))
        // }
        // console2.log("stackExchange64: %s", stackExchange64);
        // address stackExchange96;
        // assembly {
        //     stackExchange96 := calldataload(add(swapData.offset, 96))
        // }
        // console2.log("stackExchange96: %s", stackExchange96);
        // address stackExchange128;
        // assembly {
        //     stackExchange128 := calldataload(add(swapData.offset, 128))
        // }
        // console2.log("stackExchange128: %s", stackExchange128);

        /**
            `msg.data` is encoded as `abi.encodePacked(token0, token1, fee, tickLower, tickUpper, zeroForOne,
            approvalTarget, router, data)`
            | Arg            | Offset   |
            |----------------|----------|
            | token0         | [0, 20)  |
            | token1         | [20, 40) |
            | fee            | [40, 43) |
            | tickLower      | [43, 46) |
            | tickUpper      | [46, 49) |
            | zeroForOne     | [49, 50) |
            | approvalTarget | [50, 70) |
            | router         | [70, 90) |
            | data.offset    | [90, )   |
         */
        // address token0;
        // assembly {
        //     token0 := shr(96, calldataload(add(swapData.offset, 20)))
        // }
        // console2.log("token0: %s", token0);

        address token0;
        assembly {
            token0 := calldataload(add(swapData.offset, 8))
        }
        console2.log("token0: %s", token0);
        address token1;
        assembly {
            token1 := calldataload(add(swapData.offset, 28))
        }
        console2.log("token1: %s", token1);
        uint24 fee;
        assembly {
            fee := calldataload(add(swapData.offset, 31))
        }
        console2.log("fee: %s", fee);
        int24 tickLower;
        assembly {
            tickLower := calldataload(add(swapData.offset, 34))
        }
        console2.log("tickLower: %s", tickLower);
        int24 tickUpper;
        assembly {
            tickUpper := calldataload(add(swapData.offset, 37))
        }
        console2.log("tickUpper: %s", tickUpper);
        bool zeroForOne;
        assembly {
            zeroForOne := calldataload(add(swapData.offset, 38))
        }
        console2.log("zeroForOne: %s", zeroForOne);
        address approvalTarget;
        assembly {
            approvalTarget := calldataload(add(swapData.offset, 58))
        }
        console2.log("approvalTarget: %s", approvalTarget);
        address router;
        assembly {
            router := calldataload(add(swapData.offset, 78))
        }
        console2.log("router: %s", router);
    }

    function run() public view {
        // https://ethereum.stackexchange.com/questions/39989/solidity-convert-hex-string-to-bytes
        bytes memory swapData = fromHex("0000000bd2c4c865c555c30a403ed4f4c94facf482af49447d8a07e3bd95bd0d56f35241523fbab1af88d065e77c8cc2239327c5edb3a432268e5831000bb8fd114cfd1d7c0170cbb871e8f30fc8ce23609e9e0ea87b6b222f58f332761c673b59b21ff6dfa8ada44d78c12def090d5f0e3b0000000000000000000198670000000bd2c4c865c555c30a403ed4f4c94facf40000000000000000000000000000000000000000000000000004beffc03716fe0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000010000000000000000000000006f38e884725a116c9c7fbf208e79fe8828a2595f");
        this.checkRouter(swapData);
    }
}