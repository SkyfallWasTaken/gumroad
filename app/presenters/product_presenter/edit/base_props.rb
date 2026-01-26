# frozen_string_literal: true

class ProductPresenter::Edit::BaseProps
  include Rails.application.routes.url_helpers

  attr_reader :product, :pundit_user

  def initialize(product:, pundit_user:)
    @product = product
    @pundit_user = pundit_user
  end

  def props
    {
      id: product.external_id,
      unique_permalink: product.unique_permalink,
      currency_type: product.price_currency_type,
      is_tiered_membership: product.is_tiered_membership,
      is_physical: product.is_physical,
      successful_sales_count: product.successful_sales_count,
      seller: UserPresenter.new(user: product.user).author_byline_props,
      s3_url: "#{AWS_S3_ENDPOINT}/#{S3_BUCKET}",
      aws_key: AWS_ACCESS_KEY,
      dropbox_picker_api_key: DROPBOX_PICKER_API_KEY,
      product: base_product_props,
    }
  end

  private
    def base_product_props
      {
        name: product.name,
        custom_permalink: product.custom_permalink,
        is_published: !product.draft && product.alive?,
        native_type: product.native_type,
      }
    end
end
