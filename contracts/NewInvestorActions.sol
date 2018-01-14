pragma solidity ^0.4.13;

import "./NewFund.sol";
import "./FundStorage.sol";
import "./DataFeed.sol";
import "./zeppelin/DestructibleModified.sol";
import "./math/SafeMath.sol";

/**
 * @title NewInvestorActions
 * @author CoinAlpha, Inc. <contact@coinalpha.com>
 *
 * @dev This is a supporting module to the Fund contract that performs investor-related actions
 * such as subscription, redemption, allocation changes, and withdrawals.  By performing checks,
 * performing calculations and returning the updated variables to the Fund contract, this module
 * may be upgraded after the inception of the Fund contract.
 */

contract INewInvestorActions {

  function requestEthSubscription(address _addr, uint _amount)
    returns (uint, uint) {}
  function cancelEthSubscription(address _addr)
    returns (uint, uint) {}
  function calcSubscriptionShares(address _investor, uint _usdAmount)
    returns (uint, uint, uint, uint, uint, uint) {}
  function checkUsdInvestment(address _investor, uint _usdAmount)
    returns (bool) {}
  function calcEthSubscription(address _investor)
    returns (uint ethPendingSubscription, uint newTotalEthPendingSubscription) {}
  function subscribe(address _addr, uint _usdAmount)
    returns (uint, uint, uint, uint, uint, uint) {}
  

  function calcRedeemUsdInvestor(address _investor, uint _shares)
    returns (uint, uint, uint, uint, uint) {}
  function requestEthRedemption(address _addr, uint _shares)
    returns (uint, uint) {}
  function cancelEthRedemption(address addr)
    returns (uint, uint) {}
  function calcRedeemEthInvestor(address _investor)
    returns (uint, uint, uint, uint, uint, uint, uint) {}

  function redeem(address _addr)
    returns (uint, uint, uint, uint, uint, uint, uint) {}
  
  function liquidate(address _addr)
    returns (uint, uint, uint, uint, uint, uint) {}

  function withdraw(address _addr)
    returns (uint, uint, uint) {}
  
  function sharesToEth(uint _shareClass, uint _shares)
    returns (uint ethAmount) {}
}

contract NewInvestorActions is DestructibleModified {
  using SafeMath for uint;

  address public fundAddress;

  // Modules
  IDataFeed public dataFeed;
  INewFund newFund;
  IFundStorage public fundStorage;

  // This modifier is applied to all external methods in this contract since only
  // the primary Fund contract can use this module
  modifier onlyFund {
    require(msg.sender == fundAddress);
    _;
  }

  function NewInvestorActions(
    address _dataFeed,
    address _fundStorage
  )
  {
    dataFeed = IDataFeed(_dataFeed);
    fundStorage = IFundStorage(_fundStorage);
  }

  // Modifies the max investment limit allowed for an investor and overwrites the past limit
  // Used for both whitelisting a new investor and modifying an existing investor's allocation
  // function modifyAllocation(address _addr, uint _allocation)
  //   onlyFund
  //   constant
  //   returns (uint _ethTotalAllocation)
  // {
  //   require(_allocation > 0);
  //   return _allocation;
  // }

  // Get the remaining available amount in Ether that an investor can subscribe for
  // function getAvailableAllocation(address _addr)
  //   onlyFund
  //   constant
  //   returns (uint ethAvailableAllocation)
  // {
  //   var (ethTotalAllocation, ethPendingSubscription, sharesOwned, sharesPendingRedemption, ethPendingWithdrawal) = fund.getInvestor(_addr);

  //   uint ethFilledAllocation = ethPendingSubscription.add(fund.sharesToEth(sharesOwned));

  //   if (ethTotalAllocation > ethFilledAllocation) {
  //     return ethTotalAllocation.sub(ethFilledAllocation);
  //   } else {
  //     return 0;
  //   }
  // }
  
  // Register an investor's subscription request, after checking that
  // 1) the requested amount exceeds the minimum subscription amount and
  // 2) the investor's total allocation is not exceeded
  function requestEthSubscription(address _investor, uint _amount)
    onlyFund
    constant
    returns (uint, uint)
  {
    var (investorType, ethPendingSubscription, sharesOwned, shareClass) = fundStorage.getSubscriptionShares(_investor);

    require(investorType == 1);

    if (sharesOwned == 0) {
      require(_amount >= fundStorage.minInitialSubscriptionUsd().div(dataFeed.usdEth()).mul(1e18));
    } else {
      require(_amount >= fundStorage.minSubscriptionUsd().div(dataFeed.usdEth()).mul(1e18));
    }

    return (ethPendingSubscription.add(_amount),                        // new investor.ethPendingSubscription
            newFund.totalEthPendingSubscription().add(_amount)          // new totalEthPendingSubscription
           );
  }

  // Handles an investor's subscription cancellation
  function cancelEthSubscription(address _investor)
    onlyFund
    constant
    returns (uint, uint)
  {
    var (investorType, ethPendingSubscription, sharesOwned, shareClass) = fundStorage.getSubscriptionShares(_investor);

    require(investorType == 1 && ethPendingSubscription > 0);

    return (ethPendingSubscription,                                               // amount cancelled
            newFund.totalEthPendingSubscription().sub(ethPendingSubscription)     // new totalEthPendingSubscription
           );
  }

  /**
    * Check conditions of USD subscription
    * @param  _investor  USD Investor address / UID
    * @return isValid
    */
  function checkUsdInvestment(address _investor, uint _usdAmount)
    onlyFund
    constant
    returns (bool)
  {
    var (_investorType, _sharesOwned) = fundStorage.getUsdSubscriptionData(_investor);
    uint minUsdAmount = _sharesOwned == 0 ? fundStorage.minInitialSubscriptionUsd() : fundStorage.minSubscriptionUsd();

    require(_investorType == 2 && _usdAmount >= minUsdAmount);
    return true;
  }

  /**
    * Calculates new shares issued in subscription
    * @param  _investor    Investor UID or ETH Wallet Address
    * @param  _usdAmount   USD amount in cents, 1 = $0.01
    * @return              [1] Share Class index
    *                      [2] New total shares owned by investor
    *                      [3] Newly created shares
    *                      [4] New total supply of share class
    *                      [5] New total share supply of fund
    *                      [6] Subscription NAV in basis points: 1 = 0.01%
    */
  function calcSubscriptionShares(address _investor, uint _usdAmount)
    onlyFund
    constant
    returns (uint, uint, uint, uint, uint, uint)
  {
    var (investorType, ethPendingSubscription, sharesOwned, shareClass) = fundStorage.getSubscriptionShares(_investor);

    uint shares;
    if (investorType == 1) {
      // ETH subscribe
      shares = ethToShares(shareClass, ethPendingSubscription);
    } else {
      // USD subscribe
      shares = usdToShares(shareClass, _usdAmount);
    }

    return (shareClass,                                                             
            sharesOwned.add(shares),                                   // new investor.sharesOwned
            shares,                                                    // shares minted
            fundStorage.getShareClassSupply(shareClass).add(shares),   // new Share Class supply
            fundStorage.totalShareSupply().add(shares),                // new totalSupply
            fundStorage.getShareClassNavPerShare(shareClass)           // subscription nav
           );
  }

  /**
    * Calculates new totalEthPendingSubscription and checks for sufficient balance in fund
    * and ETH investor conditions
    * @param  _investor                          ETH wallet address
    * @return newTotalEthPendingSubscription     Fund's new total ETH pending subscription amount
    */
  function calcEthSubscription(address _investor)
    onlyFund
    constant
    returns (uint ethPendingSubscription, uint newTotalEthPendingSubscription)
  {
    var (investorType, _ethPendingSubscription) = fundStorage.getEthSubscriptionData(_investor);
    require(investorType == 1 && _ethPendingSubscription > 0);

    // Check that the fund balance has enough ether because the Fund contract's subscribe
    // function that calls this one will immediately transfer the subscribed amount of ether
    // to the exchange account upon function return
    uint otherPendingSubscriptions = newFund.totalEthPendingSubscription().sub(_ethPendingSubscription);
    require(_ethPendingSubscription <= newFund.balance.sub(otherPendingSubscriptions).sub(newFund.totalEthPendingWithdrawal()));

    return (_ethPendingSubscription, newFund.totalEthPendingSubscription().sub(_ethPendingSubscription));
  }

  // ====================================== REDEMPTIONS ======================================

  /**
    * Calculates change in share ownership for USD investor redemption
    * Confirm valid parameters for redemption
    * @param  _investor    Investor UID or ETH Wallet Address
    * @param  _shares      Amount in 1/100 shares: 1 unit = 0.01 shares
    * @return              [1] Share Class index
    *                      [2] New total net shares owned by investor after redemption
    *                      [3] New total supply of share class
    *                      [4] New total share supply of fund
    *                      [5] Redemption NAV in basis points: 1 = 0.01%
    */

  function calcRedeemUsdInvestor(address _investor, uint _shares)
    onlyFund
    constant
    returns (uint, uint, uint, uint, uint)
  {
    require(_shares >= fundStorage.minRedemptionShares());
    var (investorType, shareClass, sharesOwned) = fundStorage.getUsdRedemptionData(_investor);

    require(investorType == 2 && _shares <= sharesOwned);

    return (shareClass,                                                             
            sharesOwned.sub(_shares),                                  // new investor.sharesOwned
            fundStorage.getShareClassSupply(shareClass).sub(_shares),  // new Share Class supply
            fundStorage.totalShareSupply().sub(_shares),               // new totalSupply
            fundStorage.getShareClassNavPerShare(shareClass)           // redemption nav
           );
  }


  /**
    * Calculates ethPendingRedemption nad checks request conditions
    * @param  _investor    Investor UID or ETH Wallet Address
    * @param  _shares      Amount in 1/100 shares: 1 unit = 0.01 shares
    * @return              [1] new sharesPendingRedemption
    *                      [2] totalSharesPendingRedemption
    */

  // Register an investor's redemption request, after checking that
  // 1) the requested amount exceeds the minimum redemption amount and
  // 2) the investor can't redeem more than the shares they own
  function requestEthRedemption(address _investor, uint _shares)
    onlyFund
    constant
    returns (uint, uint)
  {
    require(_shares >= fundStorage.minRedemptionShares());
    var (investorType, sharesOwned, sharesPendingRedemption) = fundStorage.getEthRequestRedemptionData(_investor);

    // Investor's shares owned should be larger than existing redemption requests
    // plus this new redemption request
    require(investorType == 1 && sharesOwned >= _shares.add(sharesPendingRedemption));

    return (sharesPendingRedemption.add(_shares),                                   // new investor.sharesPendingRedemption
            newFund.totalSharesPendingRedemption().add(_shares)                     // new totalSharesPendingRedemption
           );
  }

  // Handles an investor's redemption cancellation, after checking that
  // the fund balance has enough ether to cover the withdrawal.
  // The amount is then moved from sharesPendingRedemption
  function cancelEthRedemption(address _investor)
    onlyFund
    constant
    returns (uint, uint)
  {
    var (investorType, sharesOwned, sharesPendingRedemption) = fundStorage.getEthRequestRedemptionData(_investor);

    // Investor should be an Eth investor and have shares pending redemption
    require(investorType == 1 && sharesPendingRedemption > 0);

    return (sharesPendingRedemption,                                                // new investor.sharesPendingRedemption
            newFund.totalSharesPendingRedemption().sub(sharesPendingRedemption)     // new totalSharesPendingRedemption
           );
  }

  /**
    * Calculates change in share ownership for ETH investor redemption and payment amount
    * Confirm valid parameters for redemption
    * @param  _investor    Investor ETH Wallet Address
    * @return              [1] Share Class index
    *                      [2] Redeemed shares
    *                      [3] New total net shares owned by investor after redemption
    *                      [4] New total supply of share class
    *                      [5] New total share supply of fund
    *                      [6] Redemption NAV in basis points: 1 = 0.01%
    *                      [7] ETH payment amount
    */

  function calcRedeemEthInvestor(address _investor)
    onlyFund
    constant
    returns (uint, uint, uint, uint, uint, uint, uint)
  {
    var (investorType, shareClass, sharesOwned, sharesPendingRedemption) = fundStorage.getEthRedemptionData(_investor);
    require(investorType == 1 && sharesPendingRedemption > 0);

    uint ethPayment = sharesToEth(shareClass, sharesPendingRedemption);
    require(ethPayment <= newFund.balance.sub(newFund.totalEthPendingSubscription()).sub(newFund.totalEthPendingWithdrawal()));

    uint nav = fundStorage.getShareClassNavPerShare(shareClass);                       // redemption nav
    return (shareClass,                            
            sharesPendingRedemption,                                                   // shares being redeemed
            sharesOwned.sub(sharesPendingRedemption),                                  // new investor.sharesOwned
            fundStorage.getShareClassSupply(shareClass).sub(sharesPendingRedemption),  // new Share Class supply
            fundStorage.totalShareSupply().sub(sharesPendingRedemption),               // new totalSupply
            nav,                                                                       // redemption nav
            ethPayment                                                                 // amount to be paid to investor
           );
  }


  // Processes an investor's redemption request and annilates their shares at the current navPerShare
  function redeem(address _addr)
    onlyFund
    constant
    returns (uint, uint, uint, uint, uint, uint, uint)
  {
    // var (ethTotalAllocation, ethPendingSubscription, sharesOwned, sharesPendingRedemption, ethPendingWithdrawal) = fund.getInvestor(_addr);

    // // Check that the fund balance has enough ether because after this function is processed, the ether
    // // equivalent amount can be withdrawn by the investor
    // uint amount = fund.sharesToEth(sharesPendingRedemption);
    // require(amount <= fund.balance.sub(fund.totalEthPendingSubscription()).sub(fund.totalEthPendingWithdrawal()));

    // return (sharesOwned.sub(sharesPendingRedemption),                           // new investor.sharesOwned
    //         0,                                                                  // new investor.sharesPendingRedemption
    //         ethPendingWithdrawal.add(amount),                                   // new investor.ethPendingWithdrawal
    //         sharesPendingRedemption,                                            // shares annihilated
    //         fund.totalSupply().sub(sharesPendingRedemption),                    // new totalSupply
    //         fund.totalSharesPendingRedemption().sub(sharesPendingRedemption),   // new totalSharesPendingRedemption
    //         fund.totalEthPendingWithdrawal().add(amount)                        // new totalEthPendingWithdrawal
    //       );
  }

  // Converts all of an investor's shares to ether and makes it available for withdrawal.  Also makes the investor's allocation zero to prevent future investment.
  function liquidate(address _addr)
    onlyFund
    constant
    returns (uint, uint, uint, uint, uint, uint)
  {
    // var (ethTotalAllocation, ethPendingSubscription, sharesOwned, sharesPendingRedemption, ethPendingWithdrawal) = fund.getInvestor(_addr);

    // // Check that the fund balance has enough ether because after this function is processed, the ether
    // // equivalent amount can be withdrawn by the investor.  The fund balance less total withdrawals and other
    // // investors' pending subscriptions should be larger than or equal to the liquidated amount.
    // uint otherPendingSubscriptions = fund.totalEthPendingSubscription().sub(ethPendingSubscription);
    // uint amount = fund.sharesToEth(sharesOwned).add(ethPendingSubscription);
    // require(amount <= fund.balance.sub(fund.totalEthPendingWithdrawal()).sub(otherPendingSubscriptions));

    // return (ethPendingWithdrawal.add(amount),                                   // new investor.ethPendingWithdrawal
    //         sharesOwned,                                                        // shares annihilated
    //         fund.totalEthPendingSubscription().sub(ethPendingSubscription),     // new totalEthPendingSubscription
    //         fund.totalSharesPendingRedemption().sub(sharesPendingRedemption),   // new totalSharesPendingRedemption
    //         fund.totalSupply().sub(sharesOwned),                                // new totalSupply
    //         fund.totalEthPendingWithdrawal().add(amount)                        // new totalEthPendingWithdrawal
    //        );
  }

  // Handles a withdrawal by an investor
  function withdraw(address _addr)
    onlyFund
    constant
    returns (uint, uint, uint)
  {
    // var (ethTotalAllocation, ethPendingSubscription, sharesOwned, sharesPendingRedemption, ethPendingWithdrawal) = fund.getInvestor(_addr);

    // // Check that the fund balance has enough ether to cover the withdrawal after subtracting pending subscriptions
    // // and other investors' withdrawals
    // require(ethPendingWithdrawal != 0);
    // uint otherInvestorPayments = fund.totalEthPendingWithdrawal().sub(ethPendingWithdrawal);
    // require(ethPendingWithdrawal <= fund.balance.sub(fund.totalEthPendingSubscription()).sub(otherInvestorPayments));

    // return (ethPendingWithdrawal,                                               // payment to be sent
    //         0,                                                                  // new investor.ethPendingWithdrawal
    //         fund.totalEthPendingWithdrawal().sub(ethPendingWithdrawal)          // new totalEthPendingWithdrawal
    //         );
  }


  // ********* CONVERSION CALCULATIONS *********

  /**
    * Convert USD cents amount into shares amount
    * @param  _shareClass  Index representing share class: base class = 0 (zero indexed)
    * @param  _usd         USD amount in cents, 1 = $0.01
    * @return _shares      Share amount in decimal units, 1 = 0.01 shares
    */
  function usdToShares(uint _shareClass, uint _usd)
    constant
    returns (uint shares)
  {
    return _usd.mul(10 ** fundStorage.decimals()).div(fundStorage.getShareClassNavPerShare(_shareClass));
  }

  /**
    * Convert Ether amount into shares
    * @param  _shareClass  Index representing share class: base class = 0 (zero indexed)
    * @param  _eth         ETH amount in wei
    * @return _shares      Share amount in decimal units, 1 = 0.01 shares
    */
  function ethToShares(uint _shareClass, uint _eth)
    constant
    returns (uint shares)
  {
    return usdToShares(_shareClass, ethToUsd(_eth));
  }

  /**
    * Convert share amount into USD cents amount
    * @param _shareClass  Index representing share class: base class = 0 (zero indexed)
    * @param _shares      Share amount in decimal units, 1 = 0.01 shares
    * @return usdAmount   USD amount in cents, 1 = $0.01
    */
  function sharesToUsd(uint _shareClass, uint _shares)
    constant
    returns (uint usdAmount)
  {
    return _shares.mul(fundStorage.getShareClassNavPerShare(_shareClass)).div(10 ** fundStorage.decimals());
  }

  /**
    * Convert share amount into Ether
    * @param _shareClass  Index representing share class: base class = 0 (zero indexed)
    * @param _shares      Share amount in decimal units, 1 = 0.01 shares
    * @return ethAmount   ETH amount in wei
    */
  function sharesToEth(uint _shareClass, uint _shares)
    constant
    returns (uint ethAmount)
  {
    return usdToEth(_shares.mul(fundStorage.getShareClassNavPerShare(_shareClass)).div(10 ** fundStorage.decimals()));
  }

  /**
    * Convert USD into ETH
    * @param _usd  USD amount in cents, 1 = $0.01
    * @return eth  ETH amount in wei
    */
  function usdToEth(uint _usd) 
    constant 
    returns (uint ethAmount)
  {
    return _usd.mul(1e18).div(dataFeed.usdEth());
  }

  /**
    * Convert ETH into USD
    * @param  _eth  ETH amount in wei
    * @return usd   USD amount in cents, 1 = $0.01
    */
  function ethToUsd(uint _eth) 
    constant 
    returns (uint usd)
  {
    return _eth.mul(dataFeed.usdEth()).div(1e18);
  }

  // ********* ADMIN *********

  // Update the address of the Fund contract
  function setFund(address _fund)
    onlyOwner
    returns (bool success)
  {
    newFund = INewFund(_fund);
    fundAddress = _fund;
    return true;
  }

  // Update the address of the data feed contract
  function setDataFeed(address _address) 
    onlyOwner 
    returns (bool success)
  {
    dataFeed = IDataFeed(_address);
    return true;
  }
}
