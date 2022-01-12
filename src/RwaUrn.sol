// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.6.8 <0.7.0;

import {VatAbstract, JugAbstract, DSTokenAbstract, GemJoinAbstract, DaiJoinAbstract, DaiAbstract} from "dss-interfaces/Interfaces.sol";

/**
 * @title An extension/subset of `DSMath` containing only the methods required in this file.
 */
library DSMathCustom {
    uint256 internal constant RAY = 10**27;

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "DSMath/add-overflow");
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "DSMath/sub-overflow");
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "DSMath/mul-overflow");
    }

    /**
     * @dev Divides x/y, but rounds it up.
     */
    function divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(x, sub(y, 1)) / y;
    }

    /**
     * @dev Converts `wad` (10^18) into a `rad` (10^45) by multiplying it by RAY (10^27).
     *  - wad: used for token balances
     *  - ray: used for interest rates
     *  - rad: used for Dai balances inside the Vat
     */
    function rad(uint256 wad) internal pure returns (uint256 z) {
        return mul(wad, RAY);
    }
}

/**
 * @title A vault for Real-World Assets (RWA).
 */
contract RwaUrn {
    /// @notice Dai Core module address.
    VatAbstract public immutable vat;
    /// @notice The GemJoin adapter for the gem in this urn.
    GemJoinAbstract public immutable gemJoin;
    /// @notice The adapter to mint/burn Dai tokens.
    DaiJoinAbstract public immutable daiJoin;
    /// @notice The stability fee management module.
    JugAbstract public jug;
    /// @notice The destination of Dai drawn from this urn.
    address public outputConduit;

    /// @notice Addresses with admin access on this contract. `wards[usr]`
    mapping(address => uint256) public wards;
    /// @notice Addresses with operator access on this contract. `can[usr]`
    mapping(address => uint256) public can;

    /**
     * @notice `usr` was granted admin access.
     * @param usr The user address.
     */
    event Rely(address indexed usr);
    /**
     * @notice `usr` admin access was revoked.
     * @param usr The user address.
     */
    event Deny(address indexed usr);
    /**
     * @notice `usr` was granted operator access.
     * @param usr The user address.
     */
    event Hope(address indexed usr);
    /**
     * @notice `usr` operator address was revoked.
     * @param usr The user address.
     */
    event Nope(address indexed usr);
    /**
     * @notice A contract parameter was updated.
     * @param what The changed parameter name. Currently the supported values are: "outputConduit" and "jug".
     * @param data The new value of the parameter.
     */
    event File(bytes32 indexed what, address data);
    /**
     * @notice `wad` amount of the gem was locked in the contract by `usr`.
     * @param usr The operator address.
     * @param wad The amount locked.
     */
    event Lock(address indexed usr, uint256 wad);
    /**
     * @notice `wad` amount of the gem was freed the contract by `usr`.
     * @param usr The operator address.
     * @param wad The amount freed.
     */
    event Free(address indexed usr, uint256 wad);
    /**
     * @notice `wad` amount of Dai was drawn by `usr` into `outputConduit`.
     * @param usr The operator address.
     * @param wad The amount drawn.
     */
    event Draw(address indexed usr, uint256 wad);
    /**
     * @notice `wad` amount of Dai was repaid by `usr`.
     * @param usr The operator address.
     * @param wad The amount repaid.
     */
    event Wipe(address indexed usr, uint256 wad);

    /**
     * @notice The urn outstanding balance was flushed out to `outputConduit`.
     * @dev This can happen only after `cage()` has been called on the `Vat`.
     * @param usr The operator address.
     * @param wad The amount flushed out.
     */
    event Quit(address indexed usr, uint256 wad);

    modifier auth() {
        require(wards[msg.sender] == 1, "RwaUrn/not-authorized");
        _;
    }

    modifier operator() {
        require(can[msg.sender] == 1, "RwaUrn/not-operator");
        _;
    }

    /**
     * @param vat_ Core module address.
     * @param jug_ GemJoin adapter for the gem in this urn.
     * @param gemJoin_ Adapter to mint/burn Dai tokens.
     * @param daiJoin_ Stability fee management module.
     * @param outputConduit_ Destination of Dai drawn from this urn.
     */
    constructor(
        address vat_,
        address jug_,
        address gemJoin_,
        address daiJoin_,
        address outputConduit_
    ) public {
        require(outputConduit_ != address(0), "RwaUrn/invalid-conduit");

        vat = VatAbstract(vat_);
        jug = JugAbstract(jug_);
        gemJoin = GemJoinAbstract(gemJoin_);
        daiJoin = DaiJoinAbstract(daiJoin_);
        outputConduit = outputConduit_;

        wards[msg.sender] = 1;

        DSTokenAbstract(GemJoinAbstract(gemJoin_).gem()).approve(gemJoin_, type(uint256).max);
        DaiAbstract(DaiJoinAbstract(daiJoin_).dai()).approve(daiJoin_, type(uint256).max);
        VatAbstract(vat_).hope(daiJoin_);

        emit Rely(msg.sender);
        emit File("outputConduit", outputConduit_);
        emit File("jug", jug_);
    }

    /*//////////////////////////////////
               Authorization
    //////////////////////////////////*/

    /**
     * @notice Grants `usr` admin access to this contract.
     * @param usr The user address.
     */
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    /**
     * @notice Revokes `usr` admin access from this contract.
     * @param usr The user address.
     */
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    /**
     * @notice Grants `usr` operator access to this contract.
     * @param usr The user address.
     */
    function hope(address usr) external auth {
        can[usr] = 1;
        emit Hope(usr);
    }

    /**
     * @notice Revokes `usr` admin access from this contract.
     * @param usr The user address.
     */
    function nope(address usr) external auth {
        can[usr] = 0;
        emit Nope(usr);
    }

    /*//////////////////////////////////
               Administration
    //////////////////////////////////*/

    /**
     * @notice Updates a contract parameter.
     * @param what The changed parameter name. `"outputConduit" | "jug"`
     * @param data The new value of the parameter.
     */
    function file(bytes32 what, address data) external auth {
        if (what == "outputConduit") {
            require(data != address(0), "RwaUrn/invalid-conduit");
            outputConduit = data;
        } else if (what == "jug") {
            jug = JugAbstract(data);
        } else {
            revert("RwaUrn/unrecognised-param");
        }

        emit File(what, data);
    }

    /*//////////////////////////////////
              Vault Operation
    //////////////////////////////////*/

    /**
     * @notice Locks `wad` amount of the gem in the contract.
     * @param wad The amount to lock.
     */
    function lock(uint256 wad) external operator {
        require(wad <= 2**255 - 1, "RwaUrn/overflow");

        DSTokenAbstract(gemJoin.gem()).transferFrom(msg.sender, address(this), wad);
        // join with address this
        gemJoin.join(address(this), wad);
        vat.frob(gemJoin.ilk(), address(this), address(this), address(this), int256(wad), 0);

        emit Lock(msg.sender, wad);
    }

    /**
     * @notice Frees `wad` amount of the gem from the contract.
     * @param wad The amount to free.
     */
    function free(uint256 wad) external operator {
        require(wad <= 2**255, "RwaUrn/overflow");

        vat.frob(gemJoin.ilk(), address(this), address(this), address(this), -int256(wad), 0);
        gemJoin.exit(msg.sender, wad);
        emit Free(msg.sender, wad);
    }

    /**
     * @notice Draws `wad` amount of Dai from the contract.
     * @param wad The amount to draw.
     */
    function draw(uint256 wad) external operator {
        bytes32 ilk = gemJoin.ilk();
        jug.drip(ilk);
        (, uint256 rate, , , ) = vat.ilks(ilk);

        uint256 dart = DSMathCustom.divup(DSMathCustom.rad(wad), rate);
        require(dart <= 2**255 - 1, "RwaUrn/overflow");

        vat.frob(ilk, address(this), address(this), address(this), 0, int256(dart));
        daiJoin.exit(outputConduit, wad);
        emit Draw(msg.sender, wad);
    }

    /**
     * @notice Repays `wad` amount of Dai to the contract.
     * @param wad The amount to wipe.
     */
    function wipe(uint256 wad) external {
        daiJoin.join(address(this), wad);

        bytes32 ilk = gemJoin.ilk();
        jug.drip(ilk);
        (, uint256 rate, , , ) = vat.ilks(ilk);

        uint256 dart = DSMathCustom.rad(wad) / rate;
        require(dart <= 2**255, "RwaUrn/overflow");

        vat.frob(ilk, address(this), address(this), address(this), 0, -int256(dart));
        emit Wipe(msg.sender, wad);
    }

    /**
     * @notice Flushes out any outstanding Dai balance to `outputConduit`.
     * @dev Can only be called after `cage()` has been called on the Vat.
     */
    function quit() external {
        require(vat.live() == 0, "RwaUrn/vat-still-live");

        DSTokenAbstract dai = DSTokenAbstract(daiJoin.dai());
        uint256 wad = dai.balanceOf(address(this));

        dai.transfer(outputConduit, wad);
        emit Quit(msg.sender, wad);
    }
}