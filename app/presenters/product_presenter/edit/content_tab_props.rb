# frozen_string_literal: true

class ProductPresenter::Edit::ContentTabProps
  attr_reader :product, :pundit_user

  def initialize(product:, pundit_user:)
    @product = product
    @pundit_user = pundit_user
  end

  def props
    {
      existing_files: -> { existing_files },
      product: product_props,
    }
  end

  private
    def product_props
      {
        rich_content: product.rich_content_json,
        files: files_data,
        has_same_rich_content_for_all_variants: product.has_same_rich_content_for_all_variants?,
        variants: variants_props,
      }
    end

    def variants_props
      product.alive_variants.in_order.map do |variant|
        {
          id: variant.external_id,
          name: variant.name || "",
          rich_content: variant.rich_content_json,
        }
      end
    end

    def existing_files
      product.user.alive_product_files_preferred_for_product(product)
        .limit($redis.get(RedisKey.product_presenter_existing_product_files_limit))
        .order(id: :desc)
        .includes(:alive_subtitle_files).map { _1.as_json(existing_product_file: true) }
    end

    def files_data
      files = product.alive_product_files.not_external.includes(:alive_subtitle_files).map do |file|
        {
          **file.as_json,
          subtitle_files: file.alive_subtitle_files.map(&:as_json),
        }
      end

      external_files = product.alive_product_files.external.map(&:as_json)
      files + external_files
    end
end
