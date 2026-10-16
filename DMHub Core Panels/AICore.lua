local mod = dmhub.GetModLoading()

ai = {
    --function() : number
    NumberOfAvailableTokens = function()
        return dmhub.tokensAvailable/1000
    end,

    --function(args : { messages = {{role: string, content: string}}, temperature = (number?), success = function(string) : nil, error = function(string) : nil}) : nil
    Chat = function(args)
        ---@type fun(message: string)
        local errorfn = args.error or (function() end)
        net.Post{
            url = "https://us-central1-dmtool-cad62.cloudfunctions.net/gpt",
            data = {
                messages = args.messages,
                temperature = args.temperature,
            },

            success = function(data)
                if data.error ~= nil or data.choices == nil or data.choices[1] == nil or data.choices[1].message == nil or data.choices[1].message.content == nil then
                    errorfn(data.error or "Invalid response")
                else
                    args.success(data.choices[1].message.content)
                end
            end,

            error = function(err)
                errorfn(json(err))
            end,
        }
    end,

    --function(args: { prompt = string, size = string?, removeBackground = string?, imageLibrary = string?, success = function(string) : nil, error = function(string) : nil})
    Image = function(args)
        ---@type fun(message: string)
        local errorfn = args.error or (function() end)
        net.Post{
            url = "https://us-central1-dmtool-cad62.cloudfunctions.net/gpt",
            data = {
                type = "image",
                prompt = args.prompt,
                size = args.size,
            },

            success = function(data)
                if data.error then
                    errorfn(data.error)
                    return
                end

                if data.data == nil or data.data[1] == nil or data.data[1].url == nil then
                    errorfn("Invalid response")
                    return
                end

                import:ImportImageFromURL(data.data[1].url,
                    function(path)
                        local avatarid
                        avatarid = assets:UploadImageAsset{
                            path = path,
                            imageType = args.imageLibrary or "Avatar",
                            error = function(text)
                                errorfn(text)
                            end,
                            upload = function(imageid)
                                dmhub.AddAndUploadImageToLibrary(args.imageLibrary or "Avatar", imageid)

                                args.success(imageid)
                            end,
                        }
                    end,
                    function(err)
                        printf("Error getting image.")
                    end,
                    {
                        removeBackground = args.removeBackground,
                    }
                )
            end,

            error = function(err)
                errorfn(json(err))
            end,
        }
    end,
}