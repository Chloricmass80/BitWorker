local ErrorMessages = {}

ErrorMessages.Default = "\nThis is an engine-level bug, report it with steps to reproduce it.";
ErrorMessages.Unpredictable = ErrorMessages.Default.."\nThe call has been ignored. BitWorker should still operate normally but be aware of other issues.";
ErrorMessages.CallIgnored = ErrorMessages.Default.."\nThis bug will cause unpredictablility on the Engine Level."

return ErrorMessages