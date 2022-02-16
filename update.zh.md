# 更新说明

dorahacks-qf-maci 基于 MACI 1.0 电路/合约开发。

## 在处理 messages 时使用一个 hash chain 代替 merkle tree 来批量处理

我们注意到 MACI 在 provess message 阶段时按照固定顺序来处理分批处理所有的 messages。与处理 states 不同的是，我们并不需要证明某一特定索引的 message 存在于整个 message 队列中，或者对特定索引的 message 进行修改。因此，我们更新了储存 messages 的数据结构，使用一个 hash chain 代替 MACI 1.0 中使用的 merkle tree。

在合约、电路中，均依据以下逻辑维护一个 msg hash tree:

```
hash_N+1 = hash(msg_N, hash_N)
```

在每次生成、验证 message proof 时，合约会将当前 batch 的 `batchStartHash` 及 `batchEndHash` 输入至电路，以确保 coordinator 必须以正确的顺序以此提交证明。同时，coordinator 几乎不能伪造任何一个 batch 中的消息，因为这几乎一定会导致电路中从 `batchStartHash` 迭代计算出的 `msgHash` 与传入的 `batchEndHash` 不匹配。

通过这一数据结构的改动，我们能够得到的最重要的可用性提升为：**MACI 中不再存在最大 messages 的限制**。MACI 1.0 中的 merkle tree 能储存的最大 messages 数量受到 `message_tree_depth` 的限制，因此攻击者可以通过发送大量无效 message 来破坏 MACI。而在新的设计里，通过 `message_batch_size` 来控制电路规模，而且理论最大 message 数量是无限的。

## 更新了计票最终生成的 result

在 MACI 1.0 中，tally 阶段最终生成 `results(perVOVotes)`，`spentVoiceCreditSubtotal`，`perVOSpentVoiceCredits` 三个统计信息。我们压缩了这部分信息，并且对于*可以通过这些数据计算而得到*的信息，不再重复进行统计。最终我们仅统计一个打包后的信息：

```
result = SUM(votes_user * 10e24 + votes_user ^ 2)
```

可以注意到 votes 与 votes^2 通过一个简单线型组合打包在一起，这在投票总数小于 10e12 的情况下都是没有问题的。对于[二次方投票](https://hackerlink.io/blog/guides/what-is-quadratic-voting-funding-how-did-we-improve-it/)来说，我们可以通过以下方式计算出我们需要的各种结果信息：

```
votes = SUM(votes)
community_contribution = SUM(votes^2)
_area_ = SUM(votes)^2 - SUM(votes^2)
matching = _area_ / SUM(_area_) * total_matching_pool
```

这一改动可以在不影响计票结果的情况下，一定程度上简化电路规模。

## FIX: 修复了 verify signature 时 sigS 值可能导致证明无法生成的问题

在 MACI 1.0 中，恶意攻击者可以通过填充一个大于 UNIT253_MAX 的 `sigS` 到他的 attack message 中。尽管这种数值在合法的 message 中不可能出现，但是它不仅会被认为是一个无效的 message，还会导致在电路的 `Num2Bits(253)` 中产生一个异常，从而完全阻止证明的生成。通过将 `verifySignature.circom` 中的 `Num2Bits(253)` 改为 `Num2Bits_strict()` 可以避免这个问题。

## FIX: 修复了特定 public key 可能导致证明无法生成的问题

在 MACI 1.0 中，恶意攻击者可以将他的 `encPubKey` 设置为形如：`{ x: NOT_ZERO, y: 1 }`，这会导致[电路中](https://github.com/weijiekoh/circomlib/blob/feat/poseidon-encryption/circuits/montgomery.circom#L38)产生一个异常，从而完全阻止证明的生成。我们修复了对于 `zero public key` 的判断边界，修复了这一问题。
