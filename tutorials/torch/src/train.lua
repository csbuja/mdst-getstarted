local nTrain = annot['train']['nsamples']
local nValid = annot['valid']['nsamples']
local batchSize = opt.batchSize
local testBatchSize = 4 -- opt.testBatchSize
local criterion = nn.CrossEntropyCriterion()
if opt.gpu ~= -1 then
   criterion:cuda()
end

for epoch = 1,opt.nEpochs do

   print('Epoch ' .. epoch)
   local param, gradparam = model:getParameters()
   

   local trainErr = 0
   local trainAcc = 0
   local validAcc = 0

   if opt.GPU ~= -1 then cutorch.synchronize() end
   collectgarbage()
   
   -- Compute validation accuracy
   -- put model in eval mode
   model:evaluate()
   local shuffle = torch.randperm(nValid)   
   for batch = 1,torch.floor(nValid/testBatchSize) do
      local inputs = torch.Tensor(testBatchSize, unpack(dataDim))
      local targets = torch.LongTensor(testBatchSize, 1):zero()

      local examples = shuffle:narrow(1, (batch-1)*testBatchSize+1, testBatchSize)
      inputs, targets = loadData('valid', examples, testBatchSize)
      if opt.gpu ~= -1 then
         inputs = inputsGPU:sub(1,testBatchSize):copy(inputs)
	 targets = labelsGPU:sub(1,testBatchSize):copy(targets)
      end

      -- Forward step
      local output = model:forward(inputs)
      -- Compute accuracy
      local acc = accuracy(output, targets)
      validAcc = validAcc + acc / torch.floor(nValid/testBatchSize) 
   end

   print('Validation Accuracy: ' .. validAcc)

   -- back to training mode
   model:training()
   local shuffle = torch.randperm(nTrain)   
   -- Perform training iteration
   for batch = 1,torch.floor(nTrain/batchSize) do

      print('Batch ' .. batch)
      local examples = shuffle:narrow(1, (batch-1)*batchSize+1, batchSize)
      inputs, targets = loadData('train', examples, batchSize)
      if opt.gpu ~= -1 then
         inputs = inputsGPU:sub(1,batchSize):copy(inputs)
	 targets = labelsGPU:sub(1,batchSize):copy(targets)
      end

      -- Forward step
      local output = model:forward(inputs)
      local err = criterion:forward(output, targets)

      -- Compute loss
      trainErr = trainErr + err / torch.floor(nTrain/batchSize)

      -- Backward step
      model:zeroGradParameters()
      model:backward(inputs, criterion:backward(output, targets))

      local function evalFn(x) return err, gradparam end
      optfn(evalFn, param, optimState)

      -- Compute accuracy
      local acc = accuracy(output, targets)
      trainAcc = trainAcc + acc / torch.floor(nTrain/batchSize) 
         
   end

   print('Train Accuracy: ' .. trainAcc)

   
end
