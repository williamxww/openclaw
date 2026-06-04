# 背景

adoc/claw/demo.yaml  是用来生成OPT(One Person Team)蓝图的配置文档。 
adoc/assemble/   下面的markdown文件，定义了一个 assemble agent
assemble agent 通过 demo.yaml 配置文档即可生成 一个 OPT 蓝图，然后上传MINIO。

最后组装时，运行时服务会启动一个 openclaw 的pod , 将这些蓝图文件挂载，此时这个 OPT openclaw就可以对外提供服务了。
默认情况下，OPT内部是一个多 agent的架构， main agent是负责协调多个 子agent 干活的。  每个子agent是一个领域的专家。

OPT设计器是一个web网页设计器，会指定各个agent的性格等配置， 这些配置最终都会体现到 demo.yaml 里。
