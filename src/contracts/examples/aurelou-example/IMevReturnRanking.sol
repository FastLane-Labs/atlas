// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

interface IMevReturnRanking {
    enum RankingType {
        LOW,
        MEDIUM,
        HIGH
    }

    function getUserRanking(address user) external view returns (IMevReturnRanking.RankingType);
}
