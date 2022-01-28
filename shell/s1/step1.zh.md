# Step 1

编译两个电路，生成：
- 将 input 转化成见证者文件 `.wtns` 的相关脚本 `/build/msg_js` 及 `/build/tally_js` 。
- 各自的 `.r1cs` 文件

### 性能

    运行环境: AMD Ryzen 5 5600X 6-Core Processor

    电路配置:
      stateTreeDepth: 7
      intStateTreeDepth: 3
      voteOptionsTreeDepth: 3
      batchSize: 125
    
    circom-msg.sh:
      编译时间: 556s
      电路规模: 2656048
    
    circom-tally.sh:
      编译时间: 547s
      电路规模: 1423661
