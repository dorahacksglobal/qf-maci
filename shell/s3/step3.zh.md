# Step 1

- 将链上合约中记录的信息全部同步下来（主要通过 `js/getContractLogs.js`）
- 处理 `messages` 并拆分成多个 `inputs.json`（主要通过 `js/genInputs/js`）
- 生成每个 `proof` 文件，并直接生成调用合约的 `data`

### 性能

    运行环境: AMD Ryzen 5 5600X 6-Core Processor

    电路配置:
      stateTreeDepth: 7
      intStateTreeDepth: 3
      voteOptionsTreeDepth: 3
      batchSize: 125
    
    proof.sh:
      生成每个 msg proof: 84s
      生成每个 tally proof: 51s
