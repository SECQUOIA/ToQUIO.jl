MOIU.@model(
    QUIOModel,                                        # model_name
    (),                                               # untyped scalar sets
    (EQ, LT, GT, MOI.Interval),                       #   typed scalar sets
    (MOI.Zeros, MOI.Nonnegatives, MOI.Nonpositives),  # untyped vector sets
    (),                                               #   typed vector sets
    (),                                               # untyped scalar functions
    (MOI.ScalarAffineFunction,),                      #   typed scalar functions
    (MOI.VectorOfVariables,),                         # untyped vector functions
    (MOI.VectorAffineFunction,),                      #   typed vector functions
    false,                                            # is_optimizer
)