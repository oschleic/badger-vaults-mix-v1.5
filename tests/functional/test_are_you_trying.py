from brownie import *
from helpers.constants import MaxUint256


def test_are_you_trying(deployer, vault, strategy, want, governance):
    """
    Verifies that you set up the Strategy properly
    """
    # Setup
    startingBalance = want.balanceOf(deployer)

    depositAmount = startingBalance // 2
    assert startingBalance >= depositAmount
    assert startingBalance >= 0
    # End Setup

    # Deposit
    assert want.balanceOf(vault) == 0

    want.approve(vault, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})

    available = vault.available()
    assert available > 0

    vault.earn({"from": governance})

    chain.sleep(10000 * 13)  # Mine so we get some interest

    ## TEST 1: Does the want get used in any way?
    assert want.balanceOf(vault) == depositAmount - available

    # Did the strategy do something with the asset?
    assert want.balanceOf(strategy) < available

    # Use this if it should invest all
    # assert want.balanceOf(strategy) == 0

    # Change to this if the strat is supposed to hodl and do nothing
    # assert strategy.balanceOf(want) = depositAmount

    ## TEST 2: Is the Harvest profitable?
    harvest = strategy.harvest({"from": governance})
    event = harvest.events["Harvested"]
    # If it doesn't print, we don't want it
    assert event["amount"] > 0

    ## TEST 3: Does the strategy emit anything? See test_custom.py for custom test
    #event = harvest.events["TreeDistribution"]
    #assert event["token"] == "TOKEN" ## Add token you emit
    #assert event["amount"] > 0 ## We want it to emit something