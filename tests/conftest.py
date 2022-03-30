import time
# ganache-cli --port 8545 --gasLimit 12000000 --accounts 11 --hardfork istanbul --mnemonic brownie --fork https://rpc.ftm.tools --chain.chainId 250 --unlock 0x7fce87e203501c3a035cbbc5f0ee72661976d6e1 --unlock 0x2a651563c9d3af67ae0388a5c8f89b867038089e
from brownie import (
    MyStrategy,
    TheVault,
    interface,
    accounts,
)
from _setup.config import (
    WANT, 
    WHALE_ADDRESS,

    PERFORMANCE_FEE_GOVERNANCE,
    PERFORMANCE_FEE_STRATEGIST,
    WITHDRAWAL_FEE,
    MANAGEMENT_FEE,
)
from helpers.constants import MaxUint256
from rich.console import Console

console = Console()

from dotmap import DotMap
import pytest


## Accounts ##
@pytest.fixture
def deployer():
    return accounts[0]

@pytest.fixture
def user():
    return accounts[9]

@pytest.fixture
def randomUser():
    return accounts[7]


## Fund the account
@pytest.fixture
def want(deployer):
    """
        TODO: Customize this so you have the token you need for the strat
    """
    TOKEN_ADDRESS = WANT
    token = interface.IERC20Detailed(TOKEN_ADDRESS)
    WHALE = accounts.at(WHALE_ADDRESS, force=True) ## Address with tons of token

    token.transfer(deployer, token.balanceOf(WHALE), {"from": WHALE})
    return token




@pytest.fixture
def feedist(randomUser):
    wftm = interface.IERC20Detailed("0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83")
    fd = interface.IFeeDistributor("0xA5e76B97e12567bbA2e822aC68842097034C55e7")
    WFTMWHALE = accounts.at("0x2a651563c9d3af67ae0388a5c8f89b867038089e", force=True) ## Address with tons of wftm

    wftm.transfer(randomUser, wftm.balanceOf(WFTMWHALE), {"from": WFTMWHALE})
    wftm.approve(fd, MaxUint256, {"from": randomUser})
    return fd



@pytest.fixture
def strategist():
    return accounts[1]


@pytest.fixture
def keeper():
    return accounts[2]


@pytest.fixture
def guardian():
    return accounts[3]


@pytest.fixture
def governance():
    return accounts[4]

@pytest.fixture
def treasury():
    return accounts[5]


@pytest.fixture
def proxyAdmin():
    return accounts[6]



@pytest.fixture
def badgerTree():
    return accounts[8]



@pytest.fixture
def deployed(want, deployer, strategist, keeper, guardian, governance, proxyAdmin, randomUser, badgerTree):
    """
    Deploys, vault and test strategy, mock token and wires them up.
    """
    want = want


    vault = TheVault.deploy({"from": deployer})
    vault.initialize(
        want,
        governance,
        keeper,
        guardian,
        governance,
        strategist,
        badgerTree,
        "",
        "",
        [
            PERFORMANCE_FEE_GOVERNANCE,
            PERFORMANCE_FEE_STRATEGIST,
            WITHDRAWAL_FEE,
            MANAGEMENT_FEE,
        ],
    )
    vault.setStrategist(deployer, {"from": governance})
    # NOTE: TheVault starts unpaused

    strategy = MyStrategy.deploy({"from": deployer})
    strategy.initialize(vault, [want])
    # NOTE: Strategy starts unpaused

    vault.setStrategy(strategy, {"from": governance})

    return DotMap(
        deployer=deployer,
        vault=vault,
        strategy=strategy,
        want=want,
        governance=governance,
        proxyAdmin=proxyAdmin,
        randomUser=randomUser,
        performanceFeeGovernance=PERFORMANCE_FEE_GOVERNANCE,
        performanceFeeStrategist=PERFORMANCE_FEE_STRATEGIST,
        withdrawalFee=WITHDRAWAL_FEE,
        managementFee=MANAGEMENT_FEE,
        badgerTree=badgerTree
    )


## Contracts ##
@pytest.fixture
def vault(deployed):
    return deployed.vault


@pytest.fixture
def strategy(deployed):
    return deployed.strategy



@pytest.fixture
def tokens(deployed):
    return [deployed.want]

### Fees ###
@pytest.fixture
def performanceFeeGovernance(deployed):
    return deployed.performanceFeeGovernance


@pytest.fixture
def performanceFeeStrategist(deployed):
    return deployed.performanceFeeStrategist


@pytest.fixture
def withdrawalFee(deployed):
    return deployed.withdrawalFee


@pytest.fixture
def setup_share_math(deployer, vault, want, governance):

    depositAmount = int(want.balanceOf(deployer) * 0.5)
    assert depositAmount > 0
    want.approve(vault.address, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})

    vault.earn({"from": governance})

    return DotMap(depositAmount=depositAmount)


## Forces reset before each test
@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass
