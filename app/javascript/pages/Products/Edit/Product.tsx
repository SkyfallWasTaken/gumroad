import { usePage } from "@inertiajs/react";
import * as React from "react";

import { ProductEditProvider, FullEditProps } from "$app/components/ProductEdit/ProductEditProvider";
import { ProductTab } from "$app/components/ProductEdit/ProductTab";

function ProductPage() {
  const props = usePage<FullEditProps>().props;

  return (
    <ProductEditProvider props={props}>
      <ProductTab />
    </ProductEditProvider>
  );
}

export default ProductPage;
