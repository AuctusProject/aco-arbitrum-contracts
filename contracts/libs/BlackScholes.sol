// SPDX-License-Identifier: None
pragma solidity 0.8.4;

import './ABDKMath64x64.sol';

library BlackScholes {

    function getOptionPrice(
        bool isCallOption,
        uint256 strikePrice, 
        uint256 currentPrice,
        uint256 pricePrecision,
        uint256 secondsToExpire, 
        uint256 annualVolatilityPercentage,
        uint256 annualInterestRate, 
        uint256 annualDividendYield,
        uint256 percentageDataPrecision
    ) internal pure returns (uint256) {
        return ABDKMath64x64.mulu(
            _blackScholesCalculation(
                isCallOption, 
                ABDKMath64x64.divu(strikePrice, pricePrecision), 
                ABDKMath64x64.divu(currentPrice, pricePrecision), 
                ABDKMath64x64.divu(annualVolatilityPercentage, percentageDataPrecision), 
                ABDKMath64x64.divu(annualInterestRate, percentageDataPrecision), 
                ABDKMath64x64.divu(annualDividendYield, percentageDataPrecision), 
                ABDKMath64x64.divu(secondsToExpire, 0x1e13380)
            ),
            pricePrecision
        );
    }

    function _blackScholesCalculation(
        bool isCallOption,
        int128 strikePrice, 
        int128 currentPrice,
        int128 volatility,
        int128 interestRate, 
        int128 dividendYield,
        int128 expiration
    ) private pure returns (int128) {
        int128 dCalculationAux = ABDKMath64x64.mul(volatility, ABDKMath64x64.sqrt(expiration));
        int128 d1 = _d1Calculation(strikePrice, currentPrice, expiration, volatility, interestRate, dividendYield, dCalculationAux);
        int128 d2 = ABDKMath64x64.sub(d1, dCalculationAux);
        return _priceCalculation(
            isCallOption, 
            strikePrice, 
            currentPrice, 
            interestRate, 
            dividendYield, 
            expiration, 
            d1, 
            d2
        );
    }

    function _priceCalculation(
        bool isCallOption,
        int128 strikePrice, 
        int128 currentPrice,
        int128 interestRate, 
        int128 dividendYield,
        int128 expiration,
        int128 d1,
        int128 d2
    ) private pure returns (int128) {
        int128 dividendYieldFactor = _getRateFactor(dividendYield, expiration);
        int128 interestRateFactor = _getRateFactor(interestRate, expiration);
        if (isCallOption) {
            return ABDKMath64x64.sub(
                ABDKMath64x64.mul(
                    dividendYieldFactor,
                    ABDKMath64x64.mul(
                        currentPrice,
                        _normalCummulativeDistribution(d1)
                    )
                ),
                ABDKMath64x64.mul(
                    interestRateFactor,
                    ABDKMath64x64.mul(
                        strikePrice,
                        _normalCummulativeDistribution(d2)
                    )
                )
            );
        } else {
            return ABDKMath64x64.sub(
                ABDKMath64x64.mul(
                    interestRateFactor,
                    ABDKMath64x64.mul(
                        strikePrice,
                        _normalCummulativeDistribution(ABDKMath64x64.neg(d2))
                    )
                ),
                ABDKMath64x64.mul(
                    dividendYieldFactor,
                    ABDKMath64x64.mul(
                        currentPrice,
                        _normalCummulativeDistribution(ABDKMath64x64.neg(d1))
                    )
                )
            );
        }
    }

    function _normalCummulativeDistribution(int128 x) private pure returns (int128) {
        int128 z = ABDKMath64x64.div(x, 0x16a09e667f3bcc908);
        int128 t = ABDKMath64x64.div(0x10000000000000000, ABDKMath64x64.add(0x10000000000000000, ABDKMath64x64.mul(0x53dd02a4f5ee2e46, ABDKMath64x64.abs(z))));
        int128 erf = _getErf(z, t);
        int128 nerf = erf;
        if (z < 0) {
            nerf = ABDKMath64x64.neg(erf);
        }
        return ABDKMath64x64.mul(0x8000000000000000, ABDKMath64x64.add(0x10000000000000000, nerf));
    }

    function _getErf(int128 z, int128 t) private pure returns (int128) {
        int128 f = ABDKMath64x64.mul(t, ABDKMath64x64.add(0x16be1c55bae156b65, ABDKMath64x64.mul(t, ABDKMath64x64.add(-0x17401c57014c38f14, ABDKMath64x64.mul(t, 0x10fb844255a12d72e)))));
        int128 f2 = ABDKMath64x64.add(0x413c831bb169f874, ABDKMath64x64.mul(t, ABDKMath64x64.add(-0x48d4c730f051a5fe, f)));
        return ABDKMath64x64.sub(0x10000000000000000, ABDKMath64x64.mul(t, ABDKMath64x64.mul(f2, ABDKMath64x64.exp(ABDKMath64x64.mul(ABDKMath64x64.neg(z), z)))));
    }

    function _getRateFactor(int128 rate, int128 expiration) private pure returns (int128) {
        int128 rateFactor = 0x10000000000000000;
        if (rate > 0) {
            rateFactor = ABDKMath64x64.exp(ABDKMath64x64.mul(ABDKMath64x64.neg(rate), expiration));
        }
        return rateFactor;
    }
    
    function _d1Calculation(
        int128 strikePrice, 
        int128 currentPrice,
        int128 expiration, 
        int128 volatility,
        int128 interestRate, 
        int128 dividendYield,
        int128 dCalculationAux
    ) private pure returns (int128) {
        return ABDKMath64x64.div(
            ABDKMath64x64.add(
                ABDKMath64x64.ln(ABDKMath64x64.div(currentPrice, strikePrice)), 
                ABDKMath64x64.mul(
                    expiration, 
                    ABDKMath64x64.add(
                        ABDKMath64x64.sub(interestRate, dividendYield), 
                        ABDKMath64x64.div(ABDKMath64x64.mul(volatility, volatility), 0x20000000000000000)
                    )
                )
            ), 
            dCalculationAux
        );
    }
}