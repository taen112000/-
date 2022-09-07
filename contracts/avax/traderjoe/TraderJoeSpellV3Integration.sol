// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import 'OpenZeppelin/openzeppelin-contracts@4.7.3/contracts/token/ERC20/IERC20.sol';
import 'OpenZeppelin/openzeppelin-contracts@4.7.3/contracts/token/ERC20/utils/SafeERC20.sol';
import 'OpenZeppelin/openzeppelin-contracts@4.7.3/contracts/token/ERC20/extensions/IERC20Metadata.sol';

import '../../BaseIntegration.sol';
import '../../utils/HomoraMath.sol';
import '../../../interfaces/avax/IBankAVAX.sol';
import '../../../interfaces/avax/traderjoe/ITraderJoeSpellV3.sol';
import '../../../interfaces/avax/traderjoe/IBoostedMasterChefJoe.sol';
import '../../../interfaces/avax/traderjoe/IWBoostedMasterChefJoeWorker.sol';
import '../../../interfaces/avax/traderjoe/ITraderJoeFactory.sol';

import 'forge-std/console2.sol';

contract TraderJoeSpellV3Integration is BaseIntegration {
  using SafeERC20 for IERC20;
  using HomoraMath for uint;

  IBankAVAX bank; // homora bank
  ITraderJoeFactory factory; // traderjoe factory

  // addLiquidityWMasterChef(address,address,(uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256),uint256)
  bytes4 addLiquiditySelector = 0xe07d904e;

  // removeLiquidityWMasterChef(address,address,(uint256,uint256,uint256,uint256,uint256,uint256,uint256))
  bytes4 removeLiquiditySelector = 0x95723b1c;

  // harvestWMasterChef()
  bytes4 harvestRewardsSelector = 0x40a65ad2;

  uint constant PRECISION = 10**18;

  struct AddLiquidityParams {
    address tokenA; // The first token of pool
    address tokenB; // The second token of pool
    uint amtAUser; // Supplied tokenA amount
    uint amtBUser; // Supplied tokenB amount
    uint amtLPUser; // Supplied LP token amount
    uint amtABorrow; // Borrow tokenA amount
    uint amtBBorrow; // Borrow tokenB amount
    uint amtLPBorrow; // Borrow LP token amount
    uint amtAMin; // Desired tokenA amount (slippage control)
    uint amtBMin; // Desired tokenB amount (slippage control)
    uint pid; // pool id of BoostedMasterChefJoe
  }

  struct RemoveLiquidityParams {
    address tokenA; // The first token of pool
    address tokenB; // The second token of pool
    uint amtLPTake; // Amount of LP being removed from the position
    uint amtLPWithdraw; // Amount of LP being received from removing the position (remaining will be converted to tokenA, tokenB)
    uint amtARepay; // Repay tokenA amount (repay all -> type(uint).max)
    uint amtBRepay; // Repay tokenB amount (repay all -> type(uint).max)
    uint amtLPRepay; // Repay LP token amount
    uint amtAMin; // Desired tokenA amount
    uint amtBMin; // Desired tokenB amount
  }

  constructor(IBankAVAX _bank, ITraderJoeFactory _factory) {
    bank = _bank;
    factory = _factory;
  }

  function openPosition(address _spell, AddLiquidityParams memory _params)
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

    positionId = bank.execute(
      0, // (0 is reserved for opening new position)
      _spell,
      abi.encodeWithSelector(
        addLiquiditySelector,
        _params.tokenA,
        _params.tokenB,
        ITraderJoeSpellV3.Amounts(
          _params.amtAUser,
          _params.amtBUser,
          _params.amtLPUser,
          _params.amtABorrow,
          _params.amtBBorrow,
          _params.amtLPBorrow,
          _params.amtAMin,
          _params.amtBMin
        ),
        _params.pid
      )
    );

    doRefundETH();
    doRefund(_params.tokenA);
    doRefund(_params.tokenB);
    doRefund(lp);
  }

  function increasePosition(
    uint _positionId,
    address _spell,
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

    bank.execute(
      _positionId,
      _spell,
      abi.encodeWithSelector(
        addLiquiditySelector,
        _params.tokenA,
        _params.tokenB,
        ITraderJoeSpellV3.Amounts(
          _params.amtAUser,
          _params.amtBUser,
          _params.amtLPUser,
          _params.amtABorrow,
          _params.amtBBorrow,
          _params.amtLPBorrow,
          _params.amtAMin,
          _params.amtBMin
        ),
        _params.pid
      )
    );

    doRefundETH();
    doRefund(_params.tokenA);
    doRefund(_params.tokenB);
    doRefund(lp);
    doRefund(rewardToken);
  }

  function reducePosition(
    address _spell,
    uint _positionId,
    RemoveLiquidityParams memory _params
  ) external {
    address lp = factory.getPair(_params.tokenA, _params.tokenB);
    address rewardToken = getRewardToken(_positionId);

    bank.execute(
      _positionId,
      _spell,
      abi.encodeWithSelector(
        removeLiquiditySelector,
        _params.tokenA,
        _params.tokenB,
        ITraderJoeSpellV3.RepayAmounts(
          _params.amtLPTake,
          _params.amtLPWithdraw,
          _params.amtARepay,
          _params.amtBRepay,
          _params.amtLPRepay,
          _params.amtAMin,
          _params.amtBMin
        )
      )
    );

    doRefundETH();
    doRefund(_params.tokenA);
    doRefund(_params.tokenB);
    doRefund(lp);
    doRefund(rewardToken);
  }

  function harvestRewards(address _spell, uint _positionId) external {
    bank.execute(_positionId, _spell, abi.encodeWithSelector(harvestRewardsSelector));

    // find reward token address from wrapper
    address rewardToken = getRewardToken(_positionId);

    doRefund(rewardToken);
  }

  function getPendingRewards(uint _positionId) external view returns (uint pendingRewards) {
    // query position info from position id
    (, address collateralTokenAddress, uint collateralId, uint collateralAmount) = bank
      .getPositionInfo(_positionId);

    IWBoostedMasterChefJoeWorker wrapper = IWBoostedMasterChefJoeWorker(collateralTokenAddress);
    IBoostedMasterChefJoe chef = IBoostedMasterChefJoe(wrapper.chef());

    // get info for calculating rewards
    (uint pid, uint startRewardTokenPerShare) = wrapper.decodeId(collateralId);
    uint endRewardTokenPerShare = wrapper.accJoePerShare();
    (uint totalSupply, , ) = chef.userInfo(pid, address(wrapper)); // total lp from wrapper deposited in Chef

    // pending rewards separates into two parts
    // 1. pending rewards that are in the wrapper contract
    // 2. pending rewards that wrapper hasn't claimed from Chef's contract
    (uint pendingRewardFromChef, , , ) = chef.pendingTokens(pid, address(wrapper));
    endRewardTokenPerShare += (pendingRewardFromChef * PRECISION) / totalSupply;

    uint stReward = (startRewardTokenPerShare * collateralAmount).divCeil(PRECISION);
    uint enReward = (endRewardTokenPerShare * collateralAmount) / PRECISION;

    pendingRewards = (enReward > stReward) ? enReward - stReward : 0;
  }

  function getRewardToken(uint _positionId) internal view returns (address rewardToken) {
    // query position info from position id
    (, address collateralTokenAddress, , ) = bank.getPositionInfo(_positionId);

    IWBoostedMasterChefJoeWorker wrapper = IWBoostedMasterChefJoeWorker(collateralTokenAddress);

    // find reward token address from wrapper
    rewardToken = address(wrapper.joe());
  }
}