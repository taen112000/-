// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import 'OpenZeppelin/openzeppelin-contracts@4.7.3/contracts/token/ERC20/IERC20.sol';
import 'OpenZeppelin/openzeppelin-contracts@4.7.3/contracts/token/ERC20/utils/SafeERC20.sol';
import 'OpenZeppelin/openzeppelin-contracts@4.7.3/contracts/token/ERC20/extensions/IERC20Metadata.sol';

import '../../BaseIntegration.sol';
import '../../utils/HomoraMath.sol';

import '../../../interfaces/eth/IBankETH.sol';
import '../../../interfaces/eth/sushiswap/IWMasterChef.sol';
import '../../../interfaces/eth/sushiswap/IMasterChef.sol';
import '../../../interfaces/eth/sushiswap/ISushiswapSpellV1.sol';

import '../../../interfaces/eth/sushiswap/ISushiswapFactory.sol';

import 'forge-std/console2.sol';

contract SushiswapSpellV1Integration is BaseIntegration {
  using SafeERC20 for IERC20;
  using HomoraMath for uint;

  IBankETH bank; // homora bank
  ISushiswapFactory factory; // sushiswap factory

  uint constant PRECISION = 10**12;

  struct AddLiquidityParams {
    address tokenA; // The first token of pool
    address tokenB; // The second token of pool
    uint amtAUser; // Supplied tokenA amount
    uint amtBUser; // Supplied tokenB amount
    uint amtLPUser; // Supplied LP token amount
    uint amtABorrow; // Borrow tokenA amount
    uint amtBBorrow; // Borrow tokenB amount
    uint amtLPBorrow; // Borrow LP token amount (should be 0, not support borrowing LP tokens)
    uint amtAMin; // Desired tokenA amount (slippage control)
    uint amtBMin; // Desired tokenB amount (slippage control)
    uint poolId; // pool id of MasterChef
  }

  struct RemoveLiquidityParams {
    address tokenA; // The first token of pool
    address tokenB; // The second token of pool
    uint amtLPTake; // Amount of LP being removed from the position
    uint amtLPWithdraw; // Amount of LP that user receives (remainings are converted to underlying tokens).
    uint amtARepay; // Amount of tokenA that user repays (repay all -> type(uint).max)
    uint amtBRepay; // Amount of tokenB that user repays (repay all -> type(uint).max)
    uint amtLPRepay; // Amount of LP that user repays (should be 0, not support borrowing LP tokens).
    uint amtAMin; // Desired tokenA amount (slippage control)
    uint amtBMin; // Desired tokenB amount (slippage control)
  }

  constructor(IBankETH _bank, ISushiswapFactory _factory) {
    bank = _bank;
    factory = _factory;
  }

  function openPosition(ISushiswapSpellV1 _spell, AddLiquidityParams memory _params)
    external
    returns (uint positionId)
  {
    address lp = factory.getPair(_params.tokenA, _params.tokenB);

    // approve tokens
    ensureApprove(_params.tokenA, address(bank));
    ensureApprove(_params.tokenB, address(bank));
    ensureApprove(lp, address(bank));

    // transfer tokens from user
    IERC20(_params.tokenA).safeTransferFrom(msg.sender, address(this), _params.amtAUser);
    IERC20(_params.tokenB).safeTransferFrom(msg.sender, address(this), _params.amtBUser);
    IERC20(lp).safeTransferFrom(msg.sender, address(this), _params.amtLPUser);

    bytes memory executeData = abi.encodeWithSelector(
      _spell.addLiquidityWMasterChef.selector,
      _params.tokenA,
      _params.tokenB,
      ISushiswapSpellV1.Amounts(
        _params.amtAUser,
        _params.amtBUser,
        _params.amtLPUser,
        _params.amtABorrow,
        _params.amtBBorrow,
        _params.amtLPBorrow,
        _params.amtAMin,
        _params.amtBMin
      ),
      _params.poolId
    );
    // (0 is reserved for opening new position)
    positionId = bank.execute(0, address(_spell), executeData);

    doRefundETH();
    doRefund(_params.tokenA);
    doRefund(_params.tokenB);
    doRefund(lp);
  }

  function increasePosition(
    uint _positionId,
    ISushiswapSpellV1 _spell,
    AddLiquidityParams memory _params
  ) external {
    address lp = factory.getPair(_params.tokenA, _params.tokenB);
    address rewardToken = getRewardToken(_positionId);

    // approve tokens
    ensureApprove(_params.tokenA, address(bank));
    ensureApprove(_params.tokenB, address(bank));
    ensureApprove(lp, address(bank));

    // transfer tokens from user
    IERC20(_params.tokenA).safeTransferFrom(msg.sender, address(this), _params.amtAUser);
    IERC20(_params.tokenB).safeTransferFrom(msg.sender, address(this), _params.amtBUser);
    IERC20(lp).safeTransferFrom(msg.sender, address(this), _params.amtLPUser);

    bytes memory executeData = abi.encodeWithSelector(
      _spell.addLiquidityWMasterChef.selector,
      _params.tokenA,
      _params.tokenB,
      ISushiswapSpellV1.Amounts(
        _params.amtAUser,
        _params.amtBUser,
        _params.amtLPUser,
        _params.amtABorrow,
        _params.amtBBorrow,
        _params.amtLPBorrow,
        _params.amtAMin,
        _params.amtBMin
      ),
      _params.poolId
    );
    bank.execute(_positionId, address(_spell), executeData);

    doRefundETH();
    doRefund(_params.tokenA);
    doRefund(_params.tokenB);
    doRefund(lp);
    doRefund(rewardToken);
  }

  function reducePosition(
    uint _positionId,
    ISushiswapSpellV1 _spell,
    RemoveLiquidityParams memory _params
  ) external {
    address lp = factory.getPair(_params.tokenA, _params.tokenB);
    address rewardToken = getRewardToken(_positionId);

    bytes memory executeData = abi.encodeWithSelector(
      _spell.removeLiquidityWMasterChef.selector,
      _params.tokenA,
      _params.tokenB,
      ISushiswapSpellV1.RepayAmounts(
        _params.amtLPTake,
        _params.amtLPWithdraw,
        _params.amtARepay,
        _params.amtBRepay,
        _params.amtLPRepay,
        _params.amtAMin,
        _params.amtBMin
      )
    );
    bank.execute(_positionId, address(_spell), executeData);

    doRefundETH();
    doRefund(_params.tokenA);
    doRefund(_params.tokenB);
    doRefund(rewardToken);
    doRefund(lp);
  }

  function harvestRewards(uint _positionId, ISushiswapSpellV1 _spell) external {
    bank.execute(
      _positionId,
      address(_spell),
      abi.encodeWithSelector(_spell.harvestWMasterChef.selector)
    );

    address rewardToken = getRewardToken(_positionId);

    doRefund(rewardToken);
  }

  function getPendingRewards(uint _positionId) external view returns (uint pendingRewards) {
    // query position info from position id
    (, address collateralTokenAddress, uint collateralId, uint collateralAmount) = bank
      .getPositionInfo(_positionId);

    IWMasterChef wrapper = IWMasterChef(collateralTokenAddress);
    IMasterChef chef = IMasterChef(wrapper.chef());

    // get info for calculating rewards
    (uint poolId, uint startRewardTokenPerShare) = wrapper.decodeId(collateralId);
    uint endRewardTokenPerShare = calculateAccRewardPerShareChef(chef, poolId);

    uint stReward = (startRewardTokenPerShare * collateralAmount).divCeil(PRECISION);
    uint enReward = (endRewardTokenPerShare * collateralAmount) / PRECISION;

    pendingRewards = (enReward > stReward) ? enReward - stReward : 0;
  }

  function calculateAccRewardPerShareChef(IMasterChef _chef, uint _poolId)
    internal
    view
    returns (uint accSushiPerShare)
  {
    address lpToken;
    uint allocPoint;
    uint lastRewardBlock;
    (lpToken, allocPoint, lastRewardBlock, accSushiPerShare) = _chef.poolInfo(_poolId);
    if (block.number <= lastRewardBlock) {
      return accSushiPerShare;
    }
    uint lpSupply = IERC20(lpToken).balanceOf(address(_chef));
    if (lpSupply == 0) {
      lastRewardBlock = block.number;
      return accSushiPerShare;
    }
    uint multiplier = _chef.getMultiplier(lastRewardBlock, block.number);
    uint sushiReward = (multiplier * _chef.sushiPerBlock() * allocPoint) / _chef.totalAllocPoint();
    accSushiPerShare += ((sushiReward * PRECISION) / lpSupply);
  }

  function getRewardToken(uint _positionId) internal view returns (address rewardToken) {
    // query position info from position id
    (, address collateralTokenAddress, , ) = bank.getPositionInfo(_positionId);

    IWMasterChef wrapper = IWMasterChef(collateralTokenAddress);

    // find reward token address from wrapper
    rewardToken = address(wrapper.sushi());
  }
}
