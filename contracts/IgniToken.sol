// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "./interface/IUniswapV2Router.sol";
import "./interface/IUniswapFactory.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @notice IgniToken is the main token BEP20 of the entire IGNI ecosystem,
 * together with our official BEP721, they should provide a wide range of utility for the entire community.
 */
contract IgniToken is Ownable {
    mapping(address => uint256) private _balances;

    /**
     * @notice Our Tokens required variables that are needed to operate everything
     */
    uint256 private _totalSupply;
    uint8 private _decimals;
    string private _symbol;
    string private _name;
    address private _lpDestination;

    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private pausedAddress;
    mapping(address => bool) private _isIncludedInFee;
    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => uint256) private _transactionTime;

    uint256 private _basePoints = 10000;
    uint256 public marketingFeePercentage = 0;
    uint256 public fundsFeePercentage = 0;
    uint256 public liquidityFeePercentage = 0;
    uint256 public transactionBurnPercentage = 9990; // Initial antibot launch fee, after the first change it will respect the 5% limit (maxFeeItem)
    uint256 public maxTxLimit = 30000 * 10**18;
    uint256 public coolDownTimeBound = 60 * 15;
    uint256 public liquidityFeeToSell = 10000 * 10**18;
    uint256 public constant maxFeeItem = 500; 

    bool public enableFee = true;
    bool public enableCoolDown = false;
    bool public enableTxLimit = false;
    bool public enableTaxEvent = false;

    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;
    bool public enableLiquidityFeeOperation = true; // Liquify operation, marketing and funds fee
    bool public enableFeeAllAddress = true; // if enabled all addresses are subject to the fees, unless you have an exclusion registered. When disabled, only addresses from the include will be taxed.

    IUniswapV2Router public pancakeswapV2Router;
    address public pancakeswapV2Pair;

    address public marketingWallet;
    address public fundsWallet;

    event ExternalTokenTransferred(
        address externalAddress,
        address toAddress,
        uint256 amount
    );
    event BnbFromContractTransferred(uint256 amount);
    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event EnableFee(bool enable);
    event EnableCoolDown(bool enable);
    event EnableTxLimit(bool enable);
    event EnableTaxEvent(bool enable);
    event EnableFeeAllAddress(bool enable);
    event SetCoolDownTimeBound(uint256 timeInSeconds);
    event SetLiquidityFeeToSell(uint256 limit);
    event SetSellLimit(uint256 limit);
    event IncludeInFee(address account, bool includeInFee);
    event ExcludeFromFee(address account, bool includeInFee);
    event PauseAddress(address account, bool paused);
    event UnPauseAddress(address account, bool paused);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(
        string memory token_name,
        string memory short_symbol,
        uint8 token_decimals,
        uint256 token_totalSupply
    ) {
        _name = token_name;
        _symbol = short_symbol;
        _decimals = token_decimals;
        _totalSupply = token_totalSupply * 10**token_decimals;

        // Add all the tokens created to the creator of the token
        _balances[msg.sender] = _totalSupply;

        marketingWallet = msg.sender;
        fundsWallet = msg.sender;
        _lpDestination = msg.sender;
        _isExcludedFromFee[msg.sender] = true;

        // Emit an Transfer event to notify the blockchain that an Transfer has occured
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    /**
     * Init router to allow liquify
     */
    function initUniswapRouter(address uniswapV2RouterAdd, bool createPair)
        external
        onlyOwner
    {
        IUniswapV2Router _pancakeswapV2Router = IUniswapV2Router(
            uniswapV2RouterAdd
        );
        if (createPair) {
            // Create a pancakeswap pair for this new token
            pancakeswapV2Pair = IUniswapFactory(_pancakeswapV2Router.factory())
                .createPair(address(this), _pancakeswapV2Router.WETH());

            _isIncludedInFee[pancakeswapV2Pair] = true;
        }
        pancakeswapV2Router = _pancakeswapV2Router;

        // Approve router
        _approve(address(this), address(pancakeswapV2Router), _totalSupply);
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() external view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() external view virtual returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {BEP20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IBEP20-balanceOf} and {IBEP20-transfer}.
     */
    function decimals() external view virtual returns (uint8) {
        return _decimals;
    }

    /**
     * @dev See {IBEP20-totalSupply}.
     */
    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IBEP20-balanceOf}.
     */
    function balanceOf(address account)
        external
        view
        virtual
        returns (uint256)
    {
        return _balances[account];
    }

    /**
     * @dev See {IBEP20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount)
        external
        virtual
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IBEP20-allowance}.
     */
    function allowance(address owner, address spender)
        external
        view
        virtual
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IBEP20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount)
        external
        virtual
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IBEP20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {BEP20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external virtual returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(
            currentAllowance >= amount,
            "BEP20: transfer amount exceeds allowance"
        );
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IBEP20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue)
        external
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] + addedValue
        );
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IBEP20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue)
        external
        virtual
        returns (bool)
    {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(
            currentAllowance >= subtractedValue,
            "BEP20: decreased allowance below zero"
        );
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {BEP20-_burn}.
     */
    function burn(uint256 amount) external virtual returns (bool) {
        _burn(_msgSender(), amount);
        return true;
    }

    /**
     * @dev Returns true if the address is paused, and false otherwise.
     */
    function isAddressPaused(address account)
        external
        view
        virtual
        returns (bool)
    {
        return pausedAddress[account];
    }

    /**
     * Withdraw any token from contract address
     */
    function withdrawToken(address _tokenContract, uint256 _amount)
        external
        onlyOwner
    {
        require(_tokenContract != address(0), "Address cant be zero address");
        IERC20 tokenContract = IERC20(_tokenContract);
        tokenContract.transfer(msg.sender, _amount);
        emit ExternalTokenTransferred(_tokenContract, msg.sender, _amount);
    }

    /**
     * Get BNB balance of contract address
     */
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    /**
     * Withdraw BNB from contract address
     */
    function withdrawBnbFromContract(uint256 amount) external onlyOwner {
        require(amount <= getBalance());
        address payable _owner = payable(owner());
        _owner.transfer(amount);
        emit BnbFromContractTransferred(amount);
    }

    /**
     * Exclude an address from fee: it has priority over inclusion, in a scenario where one part is included and the other excluded, we will have no tax
     */
    function setExcludeFromFee(address account, bool value) external onlyOwner {
        _isExcludedFromFee[account] = value;
        emit ExcludeFromFee(account, value);
    }

    /**
     * Include an address in fee
     */
    function setIncludeInFee(address account, bool value) external onlyOwner {
        _isIncludedInFee[account] = value;
        emit IncludeInFee(account, value);
    }

    /**
     * Check if address is excluded from fee or not
     */
    function isExcludedFromFee(address account) external view returns (bool) {
        return _isExcludedFromFee[account];
    }

    /**
     * Check if address is included in fee or not
     */
    function isIncludedInFee(address account) external view returns (bool) {
        return _isIncludedInFee[account];
    }

    /**
     * Update destination for new lp, avoid safemoon security
     */
    function setLpDestination(address newLpOwner, bool useContract)
        external
        onlyOwner
    {
        if (useContract) _lpDestination = address(this);
        else _lpDestination = newLpOwner;
    }

    /**
     * Update liquidity fee percentage
     */
    function setLiquidityFeePercent(uint256 liquidityFee) external onlyOwner {
        require(liquidityFee <= maxFeeItem, "max fee");
        liquidityFeePercentage = liquidityFee;
    }

    /**
     * Update marketing  fee percentage
     */
    function setMarketingFeePercentage(uint256 marketingFee)
        external
        onlyOwner
    {
        require(marketingFee <= maxFeeItem, "max fee");
        marketingFeePercentage = marketingFee;
    }

    /**
     * Update community funds fee percentage
     */
    function setFundsFeePercent(uint256 fundsFee) external onlyOwner {
        require(fundsFee <= maxFeeItem, "max fee");
        fundsFeePercentage = fundsFee;
    }

    /**
     * Update transaction burn percentage
     */
    function setTransactionBurnPercent(uint256 transactionBurn)
        external
        onlyOwner
    {
        require(transactionBurn <= maxFeeItem, "max fee");
        transactionBurnPercentage = transactionBurn;
    }

    /**
     * Update threshold limit to sell liquidity fee
     */
    function setLiquidityFeeToSell(uint256 limit) external onlyOwner {
        liquidityFeeToSell = limit;
        emit SetLiquidityFeeToSell(limit);
    }

    /**
     * Update max transaction limit to sell
     */
    function setMaxTxLimit(uint256 limit) external onlyOwner {
        maxTxLimit = limit;
        emit SetSellLimit(limit);
    }

    /**
     * Update cool down time bound
     */
    function setCoolDownTimeBound(uint256 timeInSeconds) external onlyOwner {
        coolDownTimeBound = timeInSeconds;
        emit SetCoolDownTimeBound(timeInSeconds);
    }

    /**
     * enable / disable fee for all contract
     */
    function setEnableFee(bool enableTax) external onlyOwner {
        enableFee = enableTax;
        emit EnableFee(enableTax);
    }

    /**
     * enable / disable fee for default for all addresses
     */
    function setEnableFeeAllAddress(bool _enableFeeAllAddress)
        external
        onlyOwner
    {
        enableFeeAllAddress = _enableFeeAllAddress;
        emit EnableFeeAllAddress(_enableFeeAllAddress);
    }

    /**
     * enable / disable liquify operation fees
     */
    function setEnableLiquifyFeeOperation(bool enableLiquifyFees)
        external
        onlyOwner
    {
        enableLiquidityFeeOperation = enableLiquifyFees;
    }

    /**
     * enable / disable cool down feature
     */
    function setEnableCoolDown(bool enable) external onlyOwner {
        enableCoolDown = enable;
        emit EnableCoolDown(enable);
    }

    /**
     * enable / disable transaction limit
     */
    function setEnableTxLimit(bool enable) external onlyOwner {
        enableTxLimit = enable;
        emit EnableTxLimit(enable);
    }

    /**
     * enable / disable tax event
     */
    function setEnableTaxEvent(bool enable) external onlyOwner {
        enableTaxEvent = enable;
        emit EnableTaxEvent(enable);
    }

    /**
     * enable / disable swap and liquify
     */
    function setSwapAndLiquifyEnabled(bool _enabled) external onlyOwner {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }

    /**
     * set marketing wallet
     */
    function setMarketingWallet(address _marketingWallet) external onlyOwner {
        marketingWallet = _marketingWallet;
    }

    /**
     * set funds wallet
     */
    function setFundsWallet(address _fundsWallet) external onlyOwner {
        fundsWallet = _fundsWallet;
    }

    /**
     * to recieve BNB from pancakeswapV2Router when swaping
     */
    receive() external payable {}

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `amount` must have a balance of at least `amount`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "BEP20: transfer from the zero address");
        require(recipient != address(0), "BEP20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(
            senderBalance >= amount,
            "BEP20: transfer amount exceeds balance"
        );
        unchecked {
            _balances[sender] = senderBalance - amount;
        }

        if (
            enableFee &&
            (enableFeeAllAddress ||
                _isIncludedInFee[sender] ||
                _isIncludedInFee[recipient]) &&
            (!_isExcludedFromFee[sender] && !_isExcludedFromFee[recipient])
        ) {
            if (enableCoolDown && recipient == pancakeswapV2Pair) {
                require(
                    (block.timestamp - _transactionTime[sender]) >
                        coolDownTimeBound,
                    "BEP20: Transfer failed due to time bound"
                );
                _transactionTime[sender] = block.timestamp;
            }

            if (enableTxLimit) {
                require(
                    amount <= maxTxLimit,
                    "BEP20: Transfer exceeds transaction limit"
                );
            }

            uint256 totalFees = takeAllFees(amount, sender);

            _balances[recipient] += amount - totalFees;

            emit Transfer(sender, recipient, amount - totalFees);
        } else {
            _balances[recipient] += amount;
            emit Transfer(sender, recipient, amount);
        }
    }

    /**
     *  Calculate and take all utility fees
     */
    function takeAllFees(uint256 _amount, address _sender)
        internal
        returns (uint256)
    {
        _swapAndLiquify(_sender);

        uint256 liquidityFee = liquidityFeePercentage > 0
            ? calculateLiquidityFee(_amount)
            : 0;

        uint256 transactionBurn = transactionBurnPercentage > 0
            ? calculateTransactionBurn(_amount)
            : 0;

        uint256 transactionMarketing = marketingFeePercentage > 0
            ? calculateMarketingFee(_amount)
            : 0;

        uint256 transactionFunds = fundsFeePercentage > 0
            ? calculateFundsFee(_amount)
            : 0;

        if (liquidityFee > 0) takeLiquidity(_sender, liquidityFee);
        if (transactionBurn > 0) takeTransactionBurn(_sender, transactionBurn);
        if (transactionMarketing > 0)
            takeMarketingFee(_sender, transactionMarketing);
        if (transactionFunds > 0) takeFundsFee(_sender, transactionFunds);

        return
            transactionBurn +
            liquidityFee +
            transactionMarketing +
            transactionFunds;
    }

    /**
     *  Take marketing fee.
     */
    function takeMarketingFee(address account, uint256 transactionMarketing)
        internal
    {
        // If enableLiquidityFeeOperation enabled, the tokens will be held on the contract for later swapping,
        // otherwise they will be sent to the respective wallets.
        _balances[
            enableLiquidityFeeOperation ? address(this) : marketingWallet
        ] += transactionMarketing;

        if (enableTaxEvent)
            emit Transfer(
                account,
                enableLiquidityFeeOperation ? address(this) : marketingWallet,
                transactionMarketing
            );
    }

    /**
     *  Take marketing feee
     */
    function takeFundsFee(address account, uint256 transactionFunds) internal {
        // If enableLiquidityFeeOperation enabled, the tokens will be held on the contract for later swapping,
        // otherwise they will be sent to the respective wallets.
        _balances[
            enableLiquidityFeeOperation ? address(this) : fundsWallet
        ] += transactionFunds;

        if (enableTaxEvent)
            emit Transfer(
                account,
                enableLiquidityFeeOperation ? address(this) : fundsWallet,
                transactionFunds
            );
    }

    /**
     *  Detect liquidity fee from a transaction
     */
    function takeLiquidity(address account, uint256 liquidityFee) internal {
        _balances[address(this)] += liquidityFee;
        if (enableTaxEvent) emit Transfer(account, address(this), liquidityFee);
    }

    /**
     *  Detect transction burn amount from a transaction
     */
    function takeTransactionBurn(address account, uint256 burnAmount) internal {
        _totalSupply -= burnAmount;
        if (enableTaxEvent) emit Transfer(account, address(0), burnAmount);
    }

    /**
     *  Calculate liquidity fee for given amount
     */
    function calculateLiquidityFee(uint256 _amount)
        internal
        view
        returns (uint256)
    {
        return (_amount * liquidityFeePercentage) / _basePoints;
    }

    /**
     *  Calculate transaction burn for given amount
     */
    function calculateTransactionBurn(uint256 _amount)
        internal
        view
        returns (uint256)
    {
        return (_amount * transactionBurnPercentage) / _basePoints;
    }

    /**
     *  Calculate transaction burn for given amount
     */
    function calculateMarketingFee(uint256 _amount)
        internal
        view
        returns (uint256)
    {
        return (_amount * marketingFeePercentage) / _basePoints;
    }

    /**
     *  Calculate transaction burn for given amount
     */
    function calculateFundsFee(uint256 _amount)
        internal
        view
        returns (uint256)
    {
        return (_amount * fundsFeePercentage) / _basePoints;
    }

    /**
     *  Validate if the liquidity fee can be added to pool
     */
    function _swapAndLiquify(address from) internal {
        uint256 contractTokenBalance = _balances[address(this)];
        // is the token balance of this contract address over the min number of
        // tokens that we need to initiate a swap + liquidity lock?
        // also, don't get caught in a circular liquidity event.
        // also, don't swap & liquify if sender is pancakeswap pair.

        if (
            from != pancakeswapV2Pair &&
            !inSwapAndLiquify &&
            swapAndLiquifyEnabled &&
            contractTokenBalance >= liquidityFeeToSell
        ) {
            bool initialFeeState = enableFee;
            // remove fee if initialFeeState was true
            if (initialFeeState) enableFee = false;

            //add liquidity
            swapAndLiquify();

            // enable fee if initialFeeState was true
            if (initialFeeState) enableFee = true;
        }
    }

    /**
     * This function allows the automatic addition of liquidity, and distribution fees in BNB
     */
    function swapAndLiquify() internal lockTheSwap {
        uint256 totalFees = fundsFeePercentage +
            marketingFeePercentage +
            liquidityFeePercentage;
        if (totalFees == 0) return;

        uint256 amountToSwap = _balances[address(this)];
        uint256 otherHalf = 0;
        uint256 liqShare = 0;
        uint256 initialBalance = address(this).balance;

        if (liquidityFeePercentage > 0) {
            liqShare = (liquidityFeePercentage * _basePoints) / totalFees;
            // Determine how much of the balance for auto liquidity
            uint256 totalTksToLiq = enableLiquidityFeeOperation
                ? (amountToSwap * liqShare) / _basePoints
                : amountToSwap;
            uint256 half = totalTksToLiq / 2;
            otherHalf = totalTksToLiq - half;
            amountToSwap = amountToSwap - otherHalf;
        }

        // Swaps all tokens minus half of the auto liquidity quota
        swapTokensForEth(amountToSwap, address(this));
        // capture the contract's new BNB balance.
        uint256 newBalance = address(this).balance - initialBalance;

        if (liquidityFeePercentage > 0) {
            // Determine BNB share that will be used for liquidity
            uint256 ethForLiq = enableLiquidityFeeOperation
                ? (newBalance * (liqShare / 2)) / _basePoints // divided by 2 why only half since the other half was used for liquidity
                : newBalance;
            // add liquidity to pancakeswap
            addLiquidity(otherHalf, ethForLiq, _lpDestination);
            newBalance -= ethForLiq; // updates the remaining balance in BNB for distribution
        }

        if (fundsFeePercentage > 0 && enableLiquidityFeeOperation) {
            // distributes fees in BNB
            uint256 fundsShare = (fundsFeePercentage * _basePoints) /
                (totalFees - liquidityFeePercentage);
            uint256 ethForFunds = (newBalance * fundsShare) / _basePoints;
            payable(fundsWallet).transfer(ethForFunds);
        }

        if (marketingFeePercentage > 0 && enableLiquidityFeeOperation) {
            // distributes fees in BNB
            uint256 marketingShare = (marketingFeePercentage * _basePoints) /
                (totalFees - liquidityFeePercentage);
            uint256 ethForMkt = (newBalance * marketingShare) / _basePoints;
            payable(marketingWallet).transfer(ethForMkt);
        }
    }

    /**
     *  Swap tokens for BNB
     */
    function swapTokensForEth(uint256 tokenAmount, address swapAddress)
        internal
    {
        // generate the pancakeswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = pancakeswapV2Router.WETH();

        // make the swap
        pancakeswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of BNB
            path,
            swapAddress,
            block.timestamp
        );
    }

    /**
     *  Add to liquidity
     */
    function addLiquidity(
        uint256 tokenAmount,
        uint256 ethAmount,
        address account
    ) internal {
        // add the liquidity
        pancakeswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage
            0, // slippage
            account,
            block.timestamp
        );
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "BEP20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "BEP20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(amount > 0, "BEP20: amount must be greater than 0");
        require(
            !pausedAddress[from],
            "BEP20Pausable: token transfer while from-address paused"
        );
        require(
            !pausedAddress[to],
            "BEP20Pausable: token transfer while to-address paused"
        );
    }
}
