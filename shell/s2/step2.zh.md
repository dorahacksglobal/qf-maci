# Step 1

- 生成 zkey 文件，并且提供一次贡献。（更推荐收集公共的可信证明并生成最终的 zkey 文件）
- 导出各自的 `verification_key.json`

### 性能

    运行环境: AMD Ryzen 5 5600X 6-Core Processor

    电路配置:
      stateTreeDepth: 7
      intStateTreeDepth: 3
      voteOptionsTreeDepth: 3
      batchSize: 125
    
    g16s-msg.sh:
      生成时间: 1294s
    
    g16s-tally.sh:
      生成时间: 833s
    
    gen-zkey-msg.sh:
      生成时间: 269s
    
    gen-zkey-tally.sh:
      生成时间: 139s
