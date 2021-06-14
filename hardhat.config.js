require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers");
require("hardhat-gas-reporter");

module.exports = {
    networks: {
        hardhat: {
            allowUnlimitedContractSize: true
        },
        arbitrum: {
            url: 'https://rinkeby.arbitrum.io/rpc',
            gasPrice: 0,
        }
    },
    mocha: {
        timeout: 120000,
    },
    solidity: {
        version: "0.8.4",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200
            }
        }
    },
    gasReporter: {
        enabled: false,
        currency: 'USD',
        gasPrice: 100
    }
};
