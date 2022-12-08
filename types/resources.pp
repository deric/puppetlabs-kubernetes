# Reserved resources
type Kubernetes::Resources = Optional[Struct[{
                                Optional[cpu] => Variant[String, Numeric],
                                Optional[memory] => Variant[String, Numeric],
                                Optional[ephemeral-storage] => Variant[String, Numeric],
                              }]]
