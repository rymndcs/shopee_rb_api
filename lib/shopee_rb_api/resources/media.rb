# frozen_string_literal: true

module ShopeeRbApi
  class Media < Resources::Base
    # POST /api/v2/media_space/upload_image, multipart, one image per call. A Public-type API: signed with the
    # partner credentials only, so the shop's token is not sent. params are form fields (scene, ratio).
    # A multi-image failure shows up in #item_errors (image_info_list[].error).
    # https://open.shopee.com/documents/v2/v2.media_space.upload_image?module=91&type=1
    def upload_image(io, filename: nil, **params)
      raise ArgumentError, "io must respond to #read" unless io.respond_to?(:read)

      filename ||= io.respond_to?(:path) && io.path ? File.basename(io.path) : "image"
      fields = params.transform_keys(&:to_s).transform_values(&:to_s)
      content_type, body = Multipart.build(fields:, file: { name: "image", filename:, io: })
      session.public_post(Endpoints::UPLOAD_IMAGE, body, content_type:)
    end
  end
end
